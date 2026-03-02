#!/bin/bash
# ============================================================================
# Fix NAT Gateway and Internet Connectivity
# ============================================================================

set -e

echo "=========================================="
echo "  NAT Gateway Diagnostic & Fix"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get VPC ID
PRIMARY_VPC_ID=$(terraform output -json primary_cluster 2>/dev/null | jq -r '.vpc_id' 2>/dev/null)

if [ -z "$PRIMARY_VPC_ID" ] || [ "$PRIMARY_VPC_ID" = "null" ]; then
    echo -e "${RED}✗ Could not get VPC ID from Terraform${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Primary VPC ID: $PRIMARY_VPC_ID${NC}"
echo ""

# Check NAT Gateways
echo -e "${BLUE}Step 1: Checking NAT Gateways...${NC}"
echo ""

NAT_GWS=$(aws ec2 describe-nat-gateways --region us-east-1 \
    --filter "Name=vpc-id,Values=$PRIMARY_VPC_ID" \
    --query 'NatGateways[*].[NatGatewayId,State,SubnetId]' \
    --output table)

echo "$NAT_GWS"
echo ""

# Check if NAT Gateways are available
NAT_AVAILABLE=$(aws ec2 describe-nat-gateways --region us-east-1 \
    --filter "Name=vpc-id,Values=$PRIMARY_VPC_ID" "Name=state,Values=available" \
    --query 'NatGateways[*].NatGatewayId' \
    --output text | wc -w)

if [ "$NAT_AVAILABLE" -eq "0" ]; then
    echo -e "${RED}✗ No NAT Gateways in 'available' state!${NC}"
    echo "  NAT Gateways might still be creating or failed"
    echo ""
else
    echo -e "${GREEN}✓ $NAT_AVAILABLE NAT Gateway(s) available${NC}"
    echo ""
fi

# Check Private Route Tables
echo -e "${BLUE}Step 2: Checking Private Route Tables...${NC}"
echo ""

PRIVATE_RTS=$(aws ec2 describe-route-tables --region us-east-1 \
    --filters "Name=vpc-id,Values=$PRIMARY_VPC_ID" "Name=tag:Tier,Values=private" \
    --query 'RouteTables[*].[RouteTableId,Tags[?Key==`Name`].Value|[0]]' \
    --output table)

echo "$PRIVATE_RTS"
echo ""

# Check routes in private route tables
echo -e "${BLUE}Step 3: Checking routes to NAT Gateways...${NC}"
echo ""

PRIVATE_RT_IDS=$(aws ec2 describe-route-tables --region us-east-1 \
    --filters "Name=vpc-id,Values=$PRIMARY_VPC_ID" "Name=tag:Tier,Values=private" \
    --query 'RouteTables[*].RouteTableId' \
    --output text)

for rt_id in $PRIVATE_RT_IDS; do
    echo "Route Table: $rt_id"
    aws ec2 describe-route-tables --region us-east-1 \
        --route-table-ids $rt_id \
        --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,NatGatewayId,State]' \
        --output table
    echo ""
done

# Check if instances can reach internet
echo -e "${BLUE}Step 4: Testing internet connectivity from instance...${NC}"
echo ""

INSTANCE_ID="i-006f3b3b061fa44cb"

echo "Attempting to ping 8.8.8.8 from instance..."
aws ssm send-command \
    --region us-east-1 \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ping -c 3 8.8.8.8 || echo FAILED"]' \
    --output text --query "Command.CommandId" > /tmp/ping_cmd.txt 2>/dev/null || echo "SSM command failed"

if [ -f /tmp/ping_cmd.txt ]; then
    CMD_ID=$(cat /tmp/ping_cmd.txt)
    sleep 5
    echo ""
    echo "Ping result:"
    aws ssm get-command-invocation --region us-east-1 \
        --command-id "$CMD_ID" \
        --instance-id "$INSTANCE_ID" \
        --query "StandardOutputContent" \
        --output text 2>/dev/null || echo "Could not get result"
    rm /tmp/ping_cmd.txt
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "  Summary & Recommendations"
echo "=========================================="
echo ""

if [ "$NAT_AVAILABLE" -eq "0" ]; then
    echo -e "${RED}ISSUE: NAT Gateways not available${NC}"
    echo ""
    echo "Possible causes:"
    echo "1. NAT Gateways still creating (wait 2-3 minutes)"
    echo "2. Elastic IPs not associated"
    echo "3. Public subnets don't have IGW route"
    echo ""
    echo "Fix:"
    echo "terraform apply  # Ensure all resources are created"
    echo ""
else
    echo -e "${YELLOW}NAT Gateways exist but instances can't reach internet${NC}"
    echo ""
    echo "Possible causes:"
    echo "1. Route table associations missing"
    echo "2. Security groups blocking outbound traffic"
    echo "3. Network ACLs blocking traffic"
    echo ""
    echo "Fix: Recreate instances to retry user-data with working internet:"
    echo ""
    echo "terraform taint 'module.primary_cluster.aws_instance.vault[0]'"
    echo "terraform taint 'module.primary_cluster.aws_instance.vault[1]'"
    echo "terraform taint 'module.primary_cluster.aws_instance.vault[2]'"
    echo "terraform apply"
    echo ""
fi

echo "After fixing networking, instances will need to be recreated"
echo "so the user-data script can download and install Vault."

# Made with Bob
