# Vault DR Lab - Detailed Deployment Guide for IBM Fyre

This guide provides comprehensive step-by-step instructions for deploying the Vault Enterprise DR lab on IBM Fyre.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Provision VMs on IBM Fyre](#phase-1-provision-vms-on-ibm-fyre)
3. [Phase 2: Prepare Configuration](#phase-2-prepare-configuration)
4. [Phase 3: Deploy Using Automation Script](#phase-3-deploy-using-automation-script)
5. [Phase 4: Manual Deployment (Alternative)](#phase-4-manual-deployment-alternative)
6. [Phase 5: Configure DR Replication](#phase-5-configure-dr-replication)
7. [Phase 6: Verification](#phase-6-verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Access
- [ ] IBM Fyre account (https://fyre.ibm.com)
- [ ] Ability to provision 8 VMs on Fyre
- [ ] SSH access to provisioned VMs

### Required Credentials
- [ ] Vault Enterprise license
- [ ] AWS KMS credentials (for auto-unseal) OR
- [ ] Azure Key Vault credentials (for auto-unseal)

### Local Tools
- [ ] SSH client
- [ ] SCP (for file transfer)
- [ ] OpenSSL (for certificate generation)
- [ ] Text editor (nano, vim, or VS Code)

---

## Phase 1: Provision VMs on IBM Fyre

### Step 1.1: Access IBM Fyre Portal

1. Navigate to https://fyre.ibm.com
2. Log in with your IBM credentials
3. Go to "Request Infrastructure" or "Create Stack"

### Step 1.2: Request VMs

Request the following 8 VMs:

#### Primary Vault Cluster (3 VMs)

**VM 1: vault-primary-node-1**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 4
RAM: 8 GB
Disk: 100 GB
Network: Private network with internet access
```

**VM 2: vault-primary-node-2**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 4
RAM: 8 GB
Disk: 100 GB
Network: Same as node-1
```

**VM 3: vault-primary-node-3**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 4
RAM: 8 GB
Disk: 100 GB
Network: Same as node-1
```

#### DR Vault Cluster (3 VMs)

**VM 4: vault-dr-node-1**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 4
RAM: 8 GB
Disk: 100 GB
Network: Same as primary cluster
```

**VM 5: vault-dr-node-2**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 4
RAM: 8 GB
Disk: 100 GB
Network: Same as primary cluster
```

**VM 6: vault-dr-node-3**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 4
RAM: 8 GB
Disk: 100 GB
Network: Same as primary cluster
```

#### Load Balancers (2 VMs)

**VM 7: vault-primary-lb**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 2
RAM: 4 GB
Disk: 50 GB
Network: Same as Vault nodes
```

**VM 8: vault-dr-lb**
```
OS: Ubuntu 22.04 LTS (or RHEL 8/9)
vCPU: 2
RAM: 4 GB
Disk: 50 GB
Network: Same as Vault nodes
```

### Step 1.3: Wait for Provisioning

- Provisioning typically takes 10-30 minutes
- You'll receive email notification when VMs are ready
- **Important**: Note down all IP addresses and SSH credentials

### Step 1.4: Test SSH Access

```bash
# Test SSH to each VM
ssh -i ~/.ssh/fyre_key.pem ubuntu@<VM_IP>

# If successful, exit and continue
exit
```

---

## Phase 2: Prepare Configuration

### Step 2.1: Create Inventory File

```bash
cd vault-dr-lab-fyre

# Copy example file
cp inventory.txt.example inventory.txt

# Edit with your actual IPs
nano inventory.txt
```

**Fill in your actual IP addresses:**
```bash
# Primary Cluster
PRIMARY_NODE_1_IP=10.16.23.45    # Replace with your IP
PRIMARY_NODE_2_IP=10.16.23.46    # Replace with your IP
PRIMARY_NODE_3_IP=10.16.23.47    # Replace with your IP
PRIMARY_LB_IP=10.16.23.48        # Replace with your IP

# DR Cluster
DR_NODE_1_IP=10.16.23.49         # Replace with your IP
DR_NODE_2_IP=10.16.23.50         # Replace with your IP
DR_NODE_3_IP=10.16.23.51         # Replace with your IP
DR_LB_IP=10.16.23.52             # Replace with your IP

# SSH Configuration
SSH_USER=ubuntu                   # or root, depending on Fyre setup
SSH_KEY_PATH=~/.ssh/fyre_key.pem # Path to your SSH key
```

### Step 2.2: Create Configuration File

```bash
# Copy example file
cp config.env.example config.env

# Edit with your credentials
nano config.env
```

**For AWS KMS Auto-Unseal:**
```bash
VAULT_VERSION="1.21.1+ent"
VAULT_LICENSE="02MV4UU43BK5HGYYTOJZWFQMTMNNEWU33JLJVGU2TKNRJFGV2VKRLFGWCWJV2E2RCVKV2E2RCVKV2E2RCVKV2E2RCVKV2E2RCV"  # Your actual license

# AWS KMS Auto-Unseal
AUTO_UNSEAL_TYPE="awskms"
AWS_KMS_KEY_ID="arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# Cluster Configuration
PRIMARY_CLUSTER_NAME="primary"
DR_CLUSTER_NAME="dr"
```

**For Azure Key Vault Auto-Unseal:**
```bash
VAULT_VERSION="1.21.1+ent"
VAULT_LICENSE="YOUR_LICENSE_HERE"

# Azure Key Vault Auto-Unseal
AUTO_UNSEAL_TYPE="azurekeyvault"
AZURE_TENANT_ID="12345678-1234-1234-1234-123456789012"
AZURE_CLIENT_ID="12345678-1234-1234-1234-123456789012"
AZURE_CLIENT_SECRET="your-client-secret"
AZURE_VAULT_NAME="your-vault-name"
AZURE_KEY_NAME="your-key-name"

# Cluster Configuration
PRIMARY_CLUSTER_NAME="primary"
DR_CLUSTER_NAME="dr"
```

### Step 2.3: Verify Configuration

```bash
# Check inventory file
cat inventory.txt

# Check config file (be careful - contains secrets!)
cat config.env
```

---

## Phase 3: Deploy Using Automation Script

### Step 3.1: Make Script Executable

```bash
chmod +x deploy-to-fyre.sh
```

### Step 3.2: Run Deployment Script

```bash
./deploy-to-fyre.sh
```

You'll see an interactive menu:

```
=========================================
  Vault DR Lab - IBM Fyre Deployment
=========================================

1. Deploy Primary Cluster
2. Deploy DR Cluster
3. Deploy Both Clusters
4. Initialize Primary Cluster
5. Initialize DR Cluster
6. Full Deployment (All + Initialize)
7. Exit

Select option:
```

### Step 3.3: Choose Deployment Option

**Recommended: Option 6 (Full Deployment)**

This will:
1. Generate TLS certificates
2. Deploy Vault to all 6 nodes
3. Deploy HAProxy to both load balancers
4. Initialize both clusters
5. Display initialization keys

### Step 3.4: Save Initialization Keys

**CRITICAL**: The script will display output like this:

```
Initializing primary cluster...
Unseal Key 1: AbCdEf1234567890...
Unseal Key 2: GhIjKl1234567890...
Unseal Key 3: MnOpQr1234567890...
Unseal Key 4: StUvWx1234567890...
Unseal Key 5: YzAbCd1234567890...

Initial Root Token: s.1234567890AbCdEf...
```

**Save these keys immediately in a secure location!**

```bash
# Save to a file (on your local machine, not on Fyre)
cat > ~/vault-keys-backup.txt << EOF
Primary Cluster Keys:
Unseal Key 1: [paste key 1]
Unseal Key 2: [paste key 2]
Unseal Key 3: [paste key 3]
Unseal Key 4: [paste key 4]
Unseal Key 5: [paste key 5]
Root Token: [paste token]

DR Cluster Keys:
[repeat for DR cluster]
EOF

# Secure the file
chmod 600 ~/vault-keys-backup.txt
```

---

## Phase 4: Manual Deployment (Alternative)

If you prefer manual deployment or the script fails, follow these steps:

### Step 4.1: Generate TLS Certificates

```bash
cd vault-dr-lab-fyre
mkdir -p deployment-package

# Generate CA certificate
openssl genrsa -out deployment-package/ca-key.pem 4096
openssl req -new -x509 -days 365 -key deployment-package/ca-key.pem \
  -out deployment-package/ca-cert.pem \
  -subj "/CN=Vault Internal CA/O=IBM"

# Generate Vault certificate
openssl genrsa -out deployment-package/vault-key.pem 2048
openssl req -new -key deployment-package/vault-key.pem \
  -out deployment-package/vault.csr \
  -subj "/CN=vault.internal/O=IBM"

# Sign with CA
openssl x509 -req -in deployment-package/vault.csr \
  -CA deployment-package/ca-cert.pem \
  -CAkey deployment-package/ca-key.pem \
  -CAcreateserial -out deployment-package/vault-cert.pem -days 365

rm deployment-package/vault.csr
```

### Step 4.2: Deploy to Primary Cluster

```bash
# Source configuration
source inventory.txt
source config.env

# Deploy to each primary node
for i in 1 2 3; do
  NODE_VAR="PRIMARY_NODE_${i}_IP"
  NODE_IP="${!NODE_VAR}"
  
  echo "Deploying to primary node $i ($NODE_IP)..."
  
  # Copy files
  scp -i $SSH_KEY_PATH -r deployment-package/ $SSH_USER@$NODE_IP:/tmp/
  
  # Run installation
  ssh -i $SSH_KEY_PATH $SSH_USER@$NODE_IP << 'EOFINSTALL'
    cd /tmp/deployment-package
    # Installation commands here (see scripts/install-vault.sh)
EOFINSTALL
done
```

### Step 4.3: Deploy HAProxy

```bash
# Deploy primary load balancer
scp -i $SSH_KEY_PATH -r deployment-package/ $SSH_USER@$PRIMARY_LB_IP:/tmp/
ssh -i $SSH_KEY_PATH $SSH_USER@$PRIMARY_LB_IP << 'EOFHAPROXY'
  # HAProxy installation commands (see scripts/configure-haproxy.sh)
EOFHAPROXY
```

### Step 4.4: Initialize Clusters

```bash
# SSH to primary node 1
ssh -i $SSH_KEY_PATH $SSH_USER@$PRIMARY_NODE_1_IP

# Initialize Vault
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=1
vault operator init -key-shares=5 -key-threshold=3 | tee ~/vault-init-keys.txt

# Save the keys!
cat ~/vault-init-keys.txt
```

---

## Phase 5: Configure DR Replication

### Step 5.1: Enable DR Primary

```bash
# Connect to primary cluster
export VAULT_ADDR="https://<PRIMARY_LB_IP>:8200"
export VAULT_SKIP_VERIFY=1
export VAULT_TOKEN="<primary_root_token>"

# Enable DR primary
vault write -f sys/replication/dr/primary/enable

# Verify
vault read sys/replication/dr/status
```

### Step 5.2: Generate Secondary Token

```bash
# Generate token for DR secondary
vault write sys/replication/dr/primary/secondary-token id=dr-secondary \
  | tee dr-secondary-token.txt

# Extract the wrapping token
SECONDARY_TOKEN=$(grep "wrapping_token" dr-secondary-token.txt | awk '{print $2}')
echo $SECONDARY_TOKEN
```

### Step 5.3: Enable DR Secondary

```bash
# Connect to DR cluster
export VAULT_ADDR="https://<DR_LB_IP>:8200"
export VAULT_SKIP_VERIFY=1
export VAULT_TOKEN="<dr_root_token>"

# Enable DR secondary
vault write sys/replication/dr/secondary/enable token="$SECONDARY_TOKEN"

# Wait for replication to sync (30-60 seconds)
sleep 60

# Verify replication status
vault read sys/replication/dr/status
```

### Step 5.4: Verify Replication

```bash
# Check replication status on primary
export VAULT_ADDR="https://<PRIMARY_LB_IP>:8200"
export VAULT_TOKEN="<primary_root_token>"
vault read -format=json sys/replication/dr/status | jq

# Check replication status on DR
export VAULT_ADDR="https://<DR_LB_IP>:8200"
export VAULT_TOKEN="<dr_root_token>"
vault read -format=json sys/replication/dr/status | jq
```

---

## Phase 6: Verification

### Step 6.1: Check Vault Status

```bash
# Primary cluster
export VAULT_ADDR="https://<PRIMARY_LB_IP>:8200"
export VAULT_SKIP_VERIFY=1
vault status

# Expected output:
# Initialized: true
# Sealed: false
# HA Enabled: true
# HA Mode: active
```

### Step 6.2: Access Vault UI

Open in browser:
- Primary: `https://<PRIMARY_LB_IP>:8200/ui`
- DR: `https://<DR_LB_IP>:8200/ui`

Login with root token.

### Step 6.3: Check HAProxy Stats

Open in browser:
- Primary: `http://<PRIMARY_LB_IP>:8404`
- DR: `http://<DR_LB_IP>:8404`

Login: admin/admin

### Step 6.4: Run Basic Tests

```bash
# Write a secret to primary
export VAULT_ADDR="https://<PRIMARY_LB_IP>:8200"
export VAULT_TOKEN="<primary_root_token>"

vault secrets enable -path=secret kv-v2
vault kv put secret/test value="Hello from primary"

# Wait for replication
sleep 10

# Verify on DR (after promoting if needed)
vault kv get secret/test
```

---

## Troubleshooting

### Issue: Vault Won't Start

**Check logs:**
```bash
ssh <node_ip>
sudo journalctl -u vault -f
```

**Common causes:**
- Invalid license
- Auto-unseal credentials incorrect
- Port 8200/8201 already in use
- TLS certificate issues

**Solution:**
```bash
# Check configuration
sudo cat /etc/vault.d/vault.hcl

# Restart service
sudo systemctl restart vault

# Check status
sudo systemctl status vault
```

### Issue: Auto-Unseal Failing

**Check:**
1. AWS/Azure credentials are correct
2. KMS key exists and has proper permissions
3. Network connectivity to AWS/Azure

**Test AWS KMS access:**
```bash
aws kms describe-key --key-id <your-key-id>
```

**Test Azure Key Vault access:**
```bash
az keyvault key show --vault-name <vault-name> --name <key-name>
```

### Issue: HAProxy Health Checks Failing

**Check Vault is running:**
```bash
ssh <vault_node_ip>
sudo systemctl status vault
curl -k https://localhost:8200/v1/sys/health
```

**Check HAProxy configuration:**
```bash
ssh <lb_ip>
sudo cat /etc/haproxy/haproxy.cfg
sudo systemctl status haproxy
```

### Issue: DR Replication Not Working

**Check network connectivity:**
```bash
# From DR node, test connection to primary
curl -k https://<PRIMARY_LB_IP>:8200/v1/sys/health
```

**Check replication status:**
```bash
# On primary
vault read sys/replication/dr/status

# On DR
vault read sys/replication/dr/status
```

**Common issues:**
- Firewall blocking ports 8200, 8201
- Invalid secondary token
- Time sync issues between clusters

### Issue: Can't SSH to VMs

**Check:**
1. SSH key path is correct
2. SSH user is correct (ubuntu vs root)
3. VM is fully provisioned
4. Network connectivity

**Test:**
```bash
ssh -v -i ~/.ssh/fyre_key.pem ubuntu@<VM_IP>
```

### Issue: Script Fails During Deployment

**Check:**
1. inventory.txt has correct IPs
2. config.env has valid credentials
3. SSH access works to all VMs
4. All prerequisites are installed

**Run script with debug:**
```bash
bash -x ./deploy-to-fyre.sh
```

---

## Next Steps

After successful deployment:

1. **Configure Authentication**: Set up LDAP, OIDC, or other auth methods
2. **Enable Secrets Engines**: KV, Database, PKI, Transit, etc.
3. **Create Policies**: Define access control policies
4. **Test DR Scenarios**: Practice failover and switchover
5. **Run Performance Tests**: Identify bottlenecks
6. **Set Up Monitoring**: Configure metrics and logging

See [`TEST-PLAN.md`](TEST-PLAN.md:1) for comprehensive testing procedures.

---

## Support

For issues or questions:
1. Check this troubleshooting section
2. Review Vault logs on affected nodes
3. Verify network connectivity
4. Check Vault documentation: https://www.vaultproject.io/docs

---

**Deployment complete!** Your Vault DR lab is ready for testing and performance analysis.