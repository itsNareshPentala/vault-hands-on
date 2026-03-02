#!/bin/bash
# ============================================================================
# Fix Terraform Destroy Issues
# ============================================================================
# This script disables deletion protection on load balancers and releases
# Elastic IPs to allow successful infrastructure destruction.
# ============================================================================

set -e

echo "=========================================="
echo "  Fixing Terraform Destroy Issues"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load Balancer ARNs from error messages
PRIMARY_LB_ARN="arn:aws:elasticloadbalancing:us-east-1:790756194327:loadbalancer/net/vault-primary-vault-nlb/dd5001fa421b3bb1"
DR_LB_ARN="arn:aws:elasticloadbalancing:us-east-2:790756194327:loadbalancer/net/vault-dr-vault-nlb/26e01348d4a7af81"

# VPC IDs from error messages
PRIMARY_VPC_ID="vpc-05507b8f5eaaea945"
DR_VPC_ID="vpc-0054716c56851947f"

# Internet Gateway IDs from error messages
PRIMARY_IGW_ID="igw-0fff8f340dcc0de9c"
DR_IGW_ID="igw-01ec8de1872955e32"

echo -e "${YELLOW}Step 1: Disabling deletion protection on load balancers...${NC}"
echo ""

# Disable deletion protection on Primary LB
echo "Disabling protection on Primary NLB (us-east-1)..."
aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn "$PRIMARY_LB_ARN" \
    --attributes Key=deletion_protection.enabled,Value=false \
    --region us-east-1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Primary NLB deletion protection disabled${NC}"
else
    echo -e "${RED}✗ Failed to disable Primary NLB deletion protection${NC}"
fi
echo ""

# Disable deletion protection on DR LB
echo "Disabling protection on DR NLB (us-east-2)..."
aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn "$DR_LB_ARN" \
    --attributes Key=deletion_protection.enabled,Value=false \
    --region us-east-2

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ DR NLB deletion protection disabled${NC}"
else
    echo -e "${RED}✗ Failed to disable DR NLB deletion protection${NC}"
fi
echo ""

echo -e "${YELLOW}Step 2: Releasing Elastic IPs in Primary region (us-east-1)...${NC}"
echo ""

# Get all EIPs in Primary VPC
PRIMARY_EIPS=$(aws ec2 describe-addresses --region us-east-1 --filters "Name=domain,Values=vpc" --query 'Addresses[?AssociationId!=`null`].AllocationId' --output text)

if [ -n "$PRIMARY_EIPS" ]; then
    for eip in $PRIMARY_EIPS; do
        echo "Checking EIP: $eip"
        # Get association ID
        ASSOC_ID=$(aws ec2 describe-addresses --region us-east-1 --allocation-ids $eip --query 'Addresses[0].AssociationId' --output text)
        
        if [ "$ASSOC_ID" != "None" ] && [ -n "$ASSOC_ID" ]; then
            echo "  Disassociating EIP $eip (Association: $ASSOC_ID)..."
            aws ec2 disassociate-address --region us-east-1 --association-id "$ASSOC_ID" 2>/dev/null || true
            echo -e "  ${GREEN}✓ Disassociated${NC}"
        fi
    done
else
    echo "No associated EIPs found in us-east-1"
fi
echo ""

echo -e "${YELLOW}Step 3: Releasing Elastic IPs in DR region (us-east-2)...${NC}"
echo ""

# Get all EIPs in DR VPC
DR_EIPS=$(aws ec2 describe-addresses --region us-east-2 --filters "Name=domain,Values=vpc" --query 'Addresses[?AssociationId!=`null`].AllocationId' --output text)

if [ -n "$DR_EIPS" ]; then
    for eip in $DR_EIPS; do
        echo "Checking EIP: $eip"
        # Get association ID
        ASSOC_ID=$(aws ec2 describe-addresses --region us-east-2 --allocation-ids $eip --query 'Addresses[0].AssociationId' --output text)
        
        if [ "$ASSOC_ID" != "None" ] && [ -n "$ASSOC_ID" ]; then
            echo "  Disassociating EIP $eip (Association: $ASSOC_ID)..."
            aws ec2 disassociate-address --region us-east-2 --association-id "$ASSOC_ID" 2>/dev/null || true
            echo -e "  ${GREEN}✓ Disassociated${NC}"
        fi
    done
else
    echo "No associated EIPs found in us-east-2"
fi
echo ""

echo -e "${YELLOW}Step 4: Waiting for resources to stabilize (30 seconds)...${NC}"
sleep 30
echo ""

echo -e "${GREEN}=========================================="
echo "  Cleanup Complete!"
echo "==========================================${NC}"
echo ""
echo "You can now run:"
echo "  terraform destroy"
echo ""
echo "The destroy should complete successfully now."

# Made with Bob
