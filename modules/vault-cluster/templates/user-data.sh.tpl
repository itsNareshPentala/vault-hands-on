#!/bin/bash
# Vault Enterprise — full node bootstrap (auto-unseal + auto-init)
# Template variables: cluster_name, vault_version, vault_license, region,
#   kms_key_id, enable_auto_unseal, tls_s3_bucket, tls_s3_key,
#   cloudwatch_log_group, enable_cloudwatch, audit_log_group,
#   enable_audit_logging, enable_auto_init, init_s3_bucket, init_s3_key,
#   node_index

set -euo pipefail

# --- Helper functions --------------------------------------------------------

retry() {
	local max=$1 delay=$2
	shift 2
	local attempt=1
	while [ $attempt -le $max ]; do
		"$@" && return 0
		echo "Attempt $attempt/$max failed, retrying in $${delay}s..."
		sleep $delay
		attempt=$((attempt + 1))
	done
	echo "ERROR: Command failed after $max attempts: $*"
	return 1
}

wait_for_apt_lock() {
	local waited=0
	while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ||
		fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ||
		fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
		echo "Waiting for apt lock... ($waited/300s)"
		sleep 5
		waited=$((waited + 5))
		[ $waited -ge 300 ] && {
			echo "WARNING: apt lock held >5min, proceeding"
			break
		}
	done
	sleep 2
}

# --- Terraform variables -----------------------------------------------------

CLUSTER_NAME="${cluster_name}"
VAULT_VERSION="${vault_version}"
VAULT_LICENSE="${vault_license}"
REGION="${region}"
KMS_KEY_ID="${kms_key_id}"
ENABLE_AUTO_UNSEAL="${enable_auto_unseal}"
TLS_S3_BUCKET="${tls_s3_bucket}"
TLS_S3_KEY="${tls_s3_key}"
CLOUDWATCH_LOG_GROUP="${cloudwatch_log_group}"
ENABLE_CLOUDWATCH="${enable_cloudwatch}"
AUDIT_LOG_GROUP="${audit_log_group}"
ENABLE_AUDIT_LOGGING="${enable_audit_logging}"
ENABLE_AUTO_INIT="${enable_auto_init}"
INIT_S3_BUCKET="${init_s3_bucket}"
INIT_S3_KEY="${init_s3_key}"
NODE_INDEX="${node_index}"

VAULT_USER="vault"
VAULT_GROUP="vault"
VAULT_HOME="/opt/vault"
VAULT_DATA="/opt/vault/data"
VAULT_CONFIG="/etc/vault.d"
VAULT_TLS="/opt/vault/tls"

# --- Logging -----------------------------------------------------------------

exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Vault bootstrap started at $(date) ==="

# --- System packages ---------------------------------------------------------

wait_for_apt_lock
retry 3 10 apt-get update -y

wait_for_apt_lock
retry 3 10 apt-get install -y \
	curl unzip jq awscli ca-certificates gnupg lsb-release libcap2-bin

# --- Vault user & directories ------------------------------------------------

useradd --system --home $VAULT_HOME --shell /bin/false $VAULT_USER || true
mkdir -p $VAULT_HOME $VAULT_DATA $VAULT_CONFIG $VAULT_TLS /var/log/vault
chown -R $VAULT_USER:$VAULT_GROUP $VAULT_HOME $VAULT_CONFIG /var/log/vault
chmod 750 $VAULT_DATA

# --- Data volume (EBS) -------------------------------------------------------

echo "Detecting data volume..."
DATA_DEVICE=""
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 60 ]; do
	for dev in /dev/xvdf /dev/nvme1n1 /dev/sdf; do
		[ -e "$dev" ] && {
			DATA_DEVICE="$dev"
			break 2
		}
	done
	echo "Waiting for data volume... ($WAIT_COUNT/60)"
	sleep 5
	WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ -n "$DATA_DEVICE" ]; then
	echo "Found data volume at $DATA_DEVICE"
	blkid $DATA_DEVICE || mkfs.ext4 $DATA_DEVICE
	echo "$DATA_DEVICE $VAULT_DATA ext4 defaults,nofail 0 2" >>/etc/fstab
	mount -a
	chown -R $VAULT_USER:$VAULT_GROUP $VAULT_DATA
else
	echo "WARNING: No data volume found after 5min — using root volume"
	mkdir -p $VAULT_DATA
	chown -R $VAULT_USER:$VAULT_GROUP $VAULT_DATA
fi

# --- Install Vault -----------------------------------------------------------

echo "Downloading Vault $VAULT_VERSION..."
cd /tmp
VAULT_VERSION_URL=$(echo "$VAULT_VERSION" | sed 's/+/%2B/g')
VAULT_ZIP="vault_$${VAULT_VERSION}_linux_amd64.zip"
VAULT_URL="https://releases.hashicorp.com/vault/$${VAULT_VERSION_URL}/vault_$${VAULT_VERSION_URL}_linux_amd64.zip"

retry 5 15 curl -fsSL --retry 3 --retry-delay 5 -o "$VAULT_ZIP" "$VAULT_URL"

if [ ! -f "$VAULT_ZIP" ] || [ ! -s "$VAULT_ZIP" ]; then
	echo "Direct download failed — falling back to apt repo..."
	wait_for_apt_lock
	curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
	echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
		tee /etc/apt/sources.list.d/hashicorp.list
	apt-get update -y && apt-get install -y vault-enterprise
else
	unzip -o "$VAULT_ZIP" && mv vault /usr/local/bin/ && chmod +x /usr/local/bin/vault
	rm -f "$VAULT_ZIP"
fi

vault version || {
	echo "ERROR: Vault binary not working"
	exit 1
}
setcap cap_ipc_lock=+ep /usr/local/bin/vault || echo "WARNING: setcap failed"

# --- TLS certificates (S3) ---------------------------------------------------

echo "Retrieving TLS certificates from S3..."
retry 12 10 aws sts get-caller-identity --region $REGION

TLS_SECRET=""
for i in $(seq 1 10); do
	TLS_SECRET=$(aws s3 cp "s3://$TLS_S3_BUCKET/$TLS_S3_KEY" - \
		--region $REGION 2>&1) && break
	echo "S3 TLS download attempt $i/10 failed, retrying..."
	sleep 10
done
[ -z "$TLS_SECRET" ] && {
	echo "ERROR: Failed to retrieve TLS certs from S3"
	exit 1
}

echo "$TLS_SECRET" | jq -r '.ca_cert' >$VAULT_TLS/ca.crt
echo "$TLS_SECRET" | jq -r '.server_cert' >$VAULT_TLS/vault.crt
echo "$TLS_SECRET" | jq -r '.server_key' >$VAULT_TLS/vault.key

for f in $VAULT_TLS/ca.crt $VAULT_TLS/vault.crt $VAULT_TLS/vault.key; do
	[ -s "$f" ] || {
		echo "ERROR: $f is empty"
		exit 1
	}
done

chmod 644 $VAULT_TLS/ca.crt $VAULT_TLS/vault.crt
chmod 600 $VAULT_TLS/vault.key
chown -R $VAULT_USER:$VAULT_GROUP $VAULT_TLS

# --- Instance metadata (IMDSv2) ----------------------------------------------

IMDS_TOKEN=""
for i in $(seq 1 10); do
	IMDS_TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
		-H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null) && break
	echo "Waiting for IMDS... ($i/10)"
	sleep 3
done
[ -z "$IMDS_TOKEN" ] && {
	echo "ERROR: Could not obtain IMDSv2 token"
	exit 1
}

INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
	http://169.254.169.254/latest/meta-data/instance-id)
LOCAL_IPV4=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
	http://169.254.169.254/latest/meta-data/local-ipv4)

[ -z "$INSTANCE_ID" ] || [ -z "$LOCAL_IPV4" ] &&
	{
		echo "ERROR: Missing instance metadata (ID=$INSTANCE_ID IP=$LOCAL_IPV4)"
		exit 1
	}

echo "Instance: $INSTANCE_ID  IP: $LOCAL_IPV4"

# --- Vault configuration (vault.hcl) ----------------------------------------

cat >$VAULT_CONFIG/vault.hcl <<EOF
cluster_name = "$CLUSTER_NAME"
api_addr     = "https://$LOCAL_IPV4:8200"
cluster_addr = "https://$LOCAL_IPV4:8201"

listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_cert_file   = "$VAULT_TLS/vault.crt"
  tls_key_file    = "$VAULT_TLS/vault.key"
  tls_min_version = "tls12"
}

storage "raft" {
  path    = "$VAULT_DATA"
  node_id = "$INSTANCE_ID"

  retry_join {
    auto_join             = "provider=aws region=$REGION tag_key=VaultAutoJoin tag_value=true"
    auto_join_scheme      = "https"
    leader_tls_servername = "vault.$CLUSTER_NAME.internal"
    leader_ca_cert_file   = "$VAULT_TLS/ca.crt"
    leader_client_cert_file = "$VAULT_TLS/vault.crt"
    leader_client_key_file  = "$VAULT_TLS/vault.key"
  }
}

%{ if enable_auto_unseal ~}
seal "awskms" {
  region     = "${region}"
  kms_key_id = "${kms_key_id}"
}
%{ endif ~}

ui            = true
disable_mlock = true
log_level     = "info"
license_path  = "$VAULT_CONFIG/vault.hclic"

telemetry {
  disable_hostname          = false
  prometheus_retention_time = "30s"
}
EOF

echo "$VAULT_LICENSE" >$VAULT_CONFIG/vault.hclic
chmod 640 $VAULT_CONFIG/vault.hclic
chown -R $VAULT_USER:$VAULT_GROUP $VAULT_CONFIG

# --- Systemd service ---------------------------------------------------------

cat >/etc/systemd/system/vault.service <<EOF
[Unit]
Description=HashiCorp Vault Enterprise
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$VAULT_CONFIG/vault.hcl

[Service]
Type=notify
User=$VAULT_USER
Group=$VAULT_GROUP
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=$VAULT_CONFIG/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# --- CloudWatch agent --------------------------------------------------------

%{ if enable_cloudwatch ~}
echo "Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb && rm -f amazon-cloudwatch-agent.deb

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWEOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/vault/*.log",
            "log_group_name": "$CLOUDWATCH_LOG_GROUP",
            "log_stream_name": "{instance_id}/vault.log"
          }
%{ if enable_audit_logging ~}
          ,{
            "file_path": "/var/log/vault/audit.log",
            "log_group_name": "$AUDIT_LOG_GROUP",
            "log_stream_name": "{instance_id}/audit.log"
          }
%{ endif ~}
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Vault/$CLUSTER_NAME",
    "metrics_collected": {
      "cpu":  { "totalcpu": false, "measurement": ["cpu_usage_idle", "cpu_usage_iowait"] },
      "disk": { "resources": ["*"], "measurement": ["used_percent"] },
      "mem":  { "measurement": ["mem_used_percent"] }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
	-a fetch-config -m ec2 -s \
	-c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
%{ endif ~}

# --- Environment variables ---------------------------------------------------

cat >/etc/profile.d/vault.sh <<'ENVEOF'
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/opt/vault/tls/ca.crt
ENVEOF
chmod 644 /etc/profile.d/vault.sh

# /etc/environment is sourced by SSM sessions and PAM-based logins,
# unlike /etc/profile.d which only runs in interactive login shells.
cat >>/etc/environment <<'ENVFILE'
VAULT_ADDR=https://127.0.0.1:8200
VAULT_CACERT=/opt/vault/tls/ca.crt
ENVFILE

export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/opt/vault/tls/ca.crt

# --- Start Vault -------------------------------------------------------------

systemctl daemon-reload
systemctl enable vault
systemctl start vault

echo "Waiting for Vault to start..."
VAULT_STARTED=false
for i in $(seq 1 30); do
	sleep 5
	if systemctl is-active --quiet vault; then
		echo "Vault service active (attempt $i)"
		VAULT_STARTED=true
		break
	fi
	if systemctl is-failed --quiet vault; then
		echo "Vault failed — restarting..."
		journalctl -u vault --no-pager -n 10
		systemctl restart vault
	fi
done

if [ "$VAULT_STARTED" = false ]; then
	echo "ERROR: Vault failed to start after 150s"
	journalctl -u vault --no-pager -n 50
fi

# --- Auto-initialize (Node 0 only) ------------------------------------------
# Node 0 initializes the cluster and stores credentials in S3.
# Other nodes join via Raft retry_join automatically.
# KMS auto-unseal handles unsealing — no manual steps needed.

%{ if enable_auto_init ~}
echo "Auto-init enabled (NODE_INDEX=$NODE_INDEX)"

if [ "$NODE_INDEX" = "0" ]; then
	echo "Node 1 — initializing Vault cluster (Raft leader)"

	VAULT_READY=false
	for i in $(seq 1 60); do
		HTTP_CODE=$(curl -sk -o /dev/null -w "%%{http_code}" https://127.0.0.1:8200/v1/sys/health 2>/dev/null || echo "000")
		if [ "$HTTP_CODE" = "501" ] || [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "429" ]; then
			echo "Vault API responding (HTTP $HTTP_CODE) after $i attempts"
			VAULT_READY=true
			break
		fi
		echo "Waiting for Vault API... HTTP $HTTP_CODE ($i/60)"
		sleep 5
	done

	[ "$VAULT_READY" = "false" ] && {
		echo "ERROR: Vault API unavailable after 5min"
		journalctl -u vault --no-pager -n 30
		exit 1
	}

	INIT_STATUS=$(curl -sk https://127.0.0.1:8200/v1/sys/health | jq -r '.initialized' 2>/dev/null || echo "unknown")

	if [ "$INIT_STATUS" = "false" ]; then
		echo "Initializing Vault..."
		# Temporarily disable set -e so we can capture a non-zero exit code
		set +e
		INIT_OUTPUT=$(vault operator init -recovery-shares=5 -recovery-threshold=3 -format=json 2>&1)
		INIT_EXIT=$?
		set -e
		[ $INIT_EXIT -ne 0 ] && {
			echo "ERROR: vault operator init failed"
			echo "$INIT_OUTPUT"
			exit 1
		}

		ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token' 2>/dev/null)
		[ -z "$ROOT_TOKEN" ] || [ "$ROOT_TOKEN" = "null" ] && {
			echo "ERROR: No root token in init output"
			exit 1
		}

		echo "Storing credentials in S3..."
		SECRET_VALUE=$(jq -n \
			--arg root_token "$ROOT_TOKEN" \
			--argjson recovery_keys "$(echo "$INIT_OUTPUT" | jq '.recovery_keys_b64 // .unseal_keys_b64 // []')" \
			--arg cluster_name "$CLUSTER_NAME" \
			--arg initialized_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			--arg instance_id "$INSTANCE_ID" \
			'{ root_token: $root_token, recovery_keys: $recovery_keys,
         cluster_name: $cluster_name, initialized_at: $initialized_at,
         initialized_by: $instance_id }')

		SECRET_STORED=false
		for i in $(seq 1 10); do
			echo "$SECRET_VALUE" | aws s3 cp - \
				"s3://$INIT_S3_BUCKET/$INIT_S3_KEY" \
				--region "$REGION" 2>&1 && {
				SECRET_STORED=true
				break
			}
			echo "Store attempt $i/10 failed, retrying..."
			sleep 10
		done

		if [ "$SECRET_STORED" = "false" ]; then
			echo "WARNING: Could not store credentials in S3"
			echo "ROOT TOKEN (SAVE NOW): $ROOT_TOKEN"
			echo "$INIT_OUTPUT"
		else
			echo "Credentials stored: s3://$INIT_S3_BUCKET/$INIT_S3_KEY"
		fi

		# Verify auto-unseal
		for i in $(seq 1 30); do
			SEALED=$(curl -sk https://127.0.0.1:8200/v1/sys/health | jq -r '.sealed' 2>/dev/null || echo "true")
			[ "$SEALED" = "false" ] && {
				echo "Vault unsealed and active!"
				break
			}
			echo "Waiting for KMS auto-unseal... ($i/30)"
			sleep 5
		done

		export VAULT_TOKEN="$ROOT_TOKEN"
		vault status || true

	elif [ "$INIT_STATUS" = "true" ]; then
		echo "Vault already initialized — skipping (replacement instance)"
	else
		echo "WARNING: Unknown init status ($INIT_STATUS) — skipping auto-init"
	fi

else
	echo "Node $((NODE_INDEX + 1)) — joining Raft cluster as follower"
	for i in $(seq 1 60); do
		HTTP_CODE=$(curl -sk -o /dev/null -w "%%{http_code}" https://127.0.0.1:8200/v1/sys/health 2>/dev/null || echo "000")
		if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "429" ] || [ "$HTTP_CODE" = "472" ] || [ "$HTTP_CODE" = "473" ]; then
			echo "Node $((NODE_INDEX + 1)) joined cluster (HTTP $HTTP_CODE)"
			break
		fi
		echo "Node $((NODE_INDEX + 1)) waiting... HTTP $HTTP_CODE ($i/60)"
		sleep 5
	done
	vault status || true
fi
%{ else ~}
echo "Auto-init disabled. Manual initialization required:"
echo "  vault operator init -recovery-shares=5 -recovery-threshold=3"
%{ endif ~}

# --- Done --------------------------------------------------------------------

echo "=== Vault bootstrap completed at $(date) ==="
echo "Node $((NODE_INDEX + 1)) of $CLUSTER_NAME | IP: $LOCAL_IPV4"
vault status 2>/dev/null || true
