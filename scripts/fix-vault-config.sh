#!/bin/bash
# Manual fix script for Vault configuration issues
# Run this on each Vault instance via SSM or SSH

set -e

echo "=== Vault Configuration Fix Script ==="
echo "This script will:"
echo "1. Add environment variables (VAULT_ADDR, VAULT_SKIP_VERIFY)"
echo "2. Update vault.hcl with correct KMS seal configuration"
echo "3. Fix api_addr and node_id using IMDSv2"
echo "4. Restart Vault service"
echo ""

# Get instance metadata using IMDSv2
echo "Fetching instance metadata..."
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
	-H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

if [ -z "$IMDS_TOKEN" ]; then
	echo "ERROR: Failed to get IMDSv2 token"
	exit 1
fi

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
	http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
	http://169.254.169.254/latest/meta-data/local-ipv4)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
	http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Private IP: $PRIVATE_IP"
echo "Region: $REGION"

# Get KMS key ID from tags
echo "Fetching KMS key ID from instance tags..."
KMS_KEY_ID=$(aws ec2 describe-tags --region "$REGION" \
	--filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=KMSKeyId" \
	--query 'Tags[0].Value' --output text)

if [ -z "$KMS_KEY_ID" ] || [ "$KMS_KEY_ID" = "None" ]; then
	echo "WARNING: KMS key ID not found in tags. KMS auto-unseal may not work."
	KMS_KEY_ID="REPLACE_WITH_YOUR_KMS_KEY_ID"
fi

echo "KMS Key ID: $KMS_KEY_ID"

# 1. Add environment variables
echo ""
echo "=== Step 1: Adding environment variables ==="

# System-wide profile
sudo tee /etc/profile.d/vault.sh >/dev/null <<'ENVEOF'
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
ENVEOF

echo "Created /etc/profile.d/vault.sh"

# Ubuntu user's bashrc
if ! grep -q "VAULT_ADDR" /home/ubuntu/.bashrc 2>/dev/null; then
	cat >>/home/ubuntu/.bashrc <<'BASHEOF'

# Vault environment variables
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
BASHEOF
	echo "Added to /home/ubuntu/.bashrc"
fi

# Source for current session
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true

# 2. Backup and update vault.hcl
echo ""
echo "=== Step 2: Updating vault.hcl ==="

VAULT_CONFIG="/opt/vault/config/vault.hcl"

if [ ! -f "$VAULT_CONFIG" ]; then
	echo "ERROR: Vault config not found at $VAULT_CONFIG"
	exit 1
fi

# Backup original
sudo cp "$VAULT_CONFIG" "${VAULT_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
echo "Backed up original config"

# Create new config with fixes
sudo tee "$VAULT_CONFIG" >/dev/null <<VAULTEOF
# Vault Configuration - Fixed

# API listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/vault-cert.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
}

# Cluster listener
listener "tcp" {
  address       = "0.0.0.0:8201"
  tls_cert_file = "/opt/vault/tls/vault-cert.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
}

# Storage backend
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "$INSTANCE_ID"
}

# AWS KMS Auto-Unseal
seal "awskms" {
  region     = "$REGION"
  kms_key_id = "$KMS_KEY_ID"
}

# Cluster configuration
api_addr     = "https://$PRIVATE_IP:8200"
cluster_addr = "https://$PRIVATE_IP:8201"

# UI
ui = true

# Telemetry (optional)
telemetry {
  disable_hostname = true
}
VAULTEOF

echo "Updated vault.hcl with:"
echo "  - node_id: $INSTANCE_ID"
echo "  - api_addr: https://$PRIVATE_IP:8200"
echo "  - KMS seal with key: $KMS_KEY_ID"

# 3. Restart Vault service
echo ""
echo "=== Step 3: Restarting Vault service ==="

sudo systemctl stop vault
sleep 2
sudo systemctl start vault
sleep 3

# Check status
if sudo systemctl is-active --quiet vault; then
	echo "✓ Vault service is running"
else
	echo "✗ Vault service failed to start"
	echo "Check logs: sudo journalctl -u vault -n 50"
	exit 1
fi

# 4. Verify configuration
echo ""
echo "=== Step 4: Verifying configuration ==="

sleep 5 # Wait for Vault to initialize

if command -v vault &>/dev/null; then
	echo "Vault status:"
	vault status || true

	echo ""
	echo "Checking seal type..."
	SEAL_TYPE=$(vault status -format=json 2>/dev/null | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

	if [ "$SEAL_TYPE" = "awskms" ]; then
		echo "✓ Seal type is awskms (KMS auto-unseal configured)"
	else
		echo "✗ Seal type is $SEAL_TYPE (expected awskms)"
		echo "  Check KMS key ID and IAM permissions"
	fi
else
	echo "Vault CLI not available, skipping status check"
fi

echo ""
echo "=== Fix Complete ==="
echo ""
echo "Next steps:"
echo "1. Verify environment variables: echo \$VAULT_ADDR"
echo "2. Check Vault status: vault status"
echo "3. If Vault is sealed and uninitialized, initialize it:"
echo "   vault operator init -recovery-shares=5 -recovery-threshold=3"
echo "4. If Vault is sealed but initialized, it should auto-unseal with KMS"
echo ""
echo "Logs: sudo journalctl -u vault -f"

# Made with Bob
