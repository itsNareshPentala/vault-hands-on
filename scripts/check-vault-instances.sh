#!/bin/bash
# ============================================================================
# Check Vault Instance Status
# ============================================================================
# This script SSHs into Vault instances to check if Vault is running
# ============================================================================

set -e

echo "=========================================="
echo "  Vault Instance Status Checker"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get instance IDs
INSTANCE_IDS=$(aws ec2 describe-instances --region us-east-1 \
    --filters "Name=tag:Name,Values=*vault-primary*" "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]" --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo -e "${RED}✗ No running Vault instances found${NC}"
    exit 1
fi

echo -e "${BLUE}Found Vault instances:${NC}"
echo "$INSTANCE_IDS"
echo ""

# Get SSH key path
SSH_KEY=$(terraform output -json ssh_key_info 2>/dev/null | jq -r '.private_key_path' 2>/dev/null || echo "vault-ssh-key.pem")

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${YELLOW}⚠ SSH key not found at: $SSH_KEY${NC}"
    echo "Please specify the correct SSH key path"
    read -p "Enter SSH key path: " SSH_KEY
fi

echo -e "${BLUE}Using SSH key: $SSH_KEY${NC}"
echo ""

# Check first instance
FIRST_INSTANCE=$(echo "$INSTANCE_IDS" | head -1 | awk '{print $1}')
FIRST_IP=$(echo "$INSTANCE_IDS" | head -1 | awk '{print $2}')

echo "=========================================="
echo "  Checking Instance: $FIRST_INSTANCE"
echo "  IP: $FIRST_IP"
echo "=========================================="
echo ""

# Note: Instances are in private subnets, so we need a bastion or Systems Manager
echo -e "${YELLOW}Note: Instances are in private subnets${NC}"
echo "Using AWS Systems Manager Session Manager..."
echo ""

# Check if Vault service exists
echo -e "${BLUE}1. Checking if Vault service is installed...${NC}"
aws ssm send-command \
    --region us-east-1 \
    --instance-ids "$FIRST_INSTANCE" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["systemctl list-unit-files | grep vault || echo \"Vault service not found\""]' \
    --output text --query "Command.CommandId" > /tmp/cmd_id.txt 2>/dev/null || echo "SSM not available"

if [ -f /tmp/cmd_id.txt ]; then
    CMD_ID=$(cat /tmp/cmd_id.txt)
    sleep 3
    aws ssm get-command-invocation --region us-east-1 --command-id "$CMD_ID" --instance-id "$FIRST_INSTANCE" --query "StandardOutputContent" --output text 2>/dev/null || echo "Could not get output"
    rm /tmp/cmd_id.txt
fi
echo ""

# Alternative: Check via EC2 Instance Connect
echo -e "${BLUE}2. Checking Vault status via EC2 Instance Connect...${NC}"
echo ""

# Create a temporary script to run on the instance
cat > /tmp/check_vault.sh << 'EOF'
#!/bin/bash
echo "=== System Information ==="
uname -a
echo ""

echo "=== Vault Binary ==="
which vault || echo "Vault binary not found"
vault version 2>/dev/null || echo "Cannot run vault command"
echo ""

echo "=== Vault Service Status ==="
sudo systemctl status vault --no-pager || echo "Vault service not found"
echo ""

echo "=== Vault Process ==="
ps aux | grep vault | grep -v grep || echo "No Vault process running"
echo ""

echo "=== Vault Configuration ==="
ls -la /etc/vault.d/ 2>/dev/null || echo "No Vault config directory"
echo ""

echo "=== Vault Logs (last 50 lines) ==="
sudo journalctl -u vault -n 50 --no-pager 2>/dev/null || echo "No Vault logs"
echo ""

echo "=== User Data Execution ==="
ls -la /var/lib/cloud/instance/scripts/ 2>/dev/null || echo "No user-data scripts"
cat /var/log/cloud-init-output.log 2>/dev/null | tail -100 || echo "No cloud-init logs"
EOF

echo -e "${YELLOW}To manually check an instance, run:${NC}"
echo ""
echo "# Using AWS Systems Manager (if enabled):"
echo "aws ssm start-session --region us-east-1 --target $FIRST_INSTANCE"
echo ""
echo "# Or if you have a bastion host:"
echo "ssh -i $SSH_KEY ubuntu@$FIRST_IP"
echo ""
echo "# Then on the instance, run:"
echo "sudo systemctl status vault"
echo "sudo journalctl -u vault -f"
echo "vault status"
echo ""

echo "=========================================="
echo "  Common Issues and Fixes"
echo "=========================================="
echo ""
echo -e "${YELLOW}Issue 1: Vault service not installed${NC}"
echo "  Cause: User data script failed to run"
echo "  Fix: Check /var/log/cloud-init-output.log on instance"
echo ""
echo -e "${YELLOW}Issue 2: Vault service failed to start${NC}"
echo "  Cause: Invalid configuration or license"
echo "  Fix: Check 'sudo journalctl -u vault -n 100'"
echo ""
echo -e "${YELLOW}Issue 3: Vault is sealed${NC}"
echo "  Cause: Auto-unseal not working or not initialized"
echo "  Fix: Check KMS permissions and initialize Vault"
echo ""
echo -e "${YELLOW}Issue 4: Port 8200 not listening${NC}"
echo "  Cause: Vault not started or wrong bind address"
echo "  Fix: Check Vault config in /etc/vault.d/vault.hcl"
echo ""

rm -f /tmp/check_vault.sh

# Made with Bob
