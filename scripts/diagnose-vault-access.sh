#!/bin/bash
# ============================================================================
# Vault Access Diagnostic Script
# ============================================================================
# This script diagnoses why Vault UI is not accessible
# ============================================================================

set -e

echo "=========================================="
echo "  Vault Access Diagnostic Tool"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get Terraform outputs
echo -e "${BLUE}Step 1: Getting Terraform outputs...${NC}"
echo ""

PRIMARY_LB_DNS=$(terraform output -json primary_cluster 2>/dev/null | jq -r '.load_balancer.dns_name' 2>/dev/null || echo "NOT_FOUND")
DR_LB_DNS=$(terraform output -json dr_cluster 2>/dev/null | jq -r '.load_balancer.dns_name' 2>/dev/null || echo "NOT_FOUND")

if [ "$PRIMARY_LB_DNS" = "NOT_FOUND" ] || [ "$PRIMARY_LB_DNS" = "null" ]; then
    echo -e "${RED}✗ Could not get load balancer DNS from Terraform${NC}"
    echo "  Run 'terraform apply' first"
    echo ""
    echo "Available outputs:"
    terraform output 2>/dev/null | head -20
    exit 1
fi

echo -e "${GREEN}✓ Primary LB DNS: $PRIMARY_LB_DNS${NC}"
echo -e "${GREEN}✓ DR LB DNS: $DR_LB_DNS${NC}"
echo ""

# Check if LB is internal or internet-facing
echo -e "${BLUE}Step 2: Checking Load Balancer configuration...${NC}"
echo ""

PRIMARY_LB_ARN=$(aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?DNSName=='$PRIMARY_LB_DNS'].LoadBalancerArn" --output text)

if [ -n "$PRIMARY_LB_ARN" ]; then
    LB_SCHEME=$(aws elbv2 describe-load-balancers --region us-east-1 --load-balancer-arns "$PRIMARY_LB_ARN" --query "LoadBalancers[0].Scheme" --output text)
    
    if [ "$LB_SCHEME" = "internal" ]; then
        echo -e "${RED}✗ Load Balancer is INTERNAL${NC}"
        echo "  This means it only has private IPs and cannot be accessed from the internet"
        echo "  Fix: Set lb_internal = false in terraform.tfvars"
        echo ""
    else
        echo -e "${GREEN}✓ Load Balancer is INTERNET-FACING${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠ Could not find load balancer${NC}"
    echo ""
fi

# Check target health
echo -e "${BLUE}Step 3: Checking target group health...${NC}"
echo ""

TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --region us-east-1 --query "TargetGroups[?contains(LoadBalancerArns[0], 'vault-primary')].TargetGroupArn" --output text | head -1)

if [ -n "$TARGET_GROUP_ARN" ]; then
    echo "Target Group: $TARGET_GROUP_ARN"
    echo ""
    
    TARGET_HEALTH=$(aws elbv2 describe-target-health --region us-east-1 --target-group-arn "$TARGET_GROUP_ARN" --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]" --output table)
    
    echo "$TARGET_HEALTH"
    echo ""
    
    HEALTHY_COUNT=$(echo "$TARGET_HEALTH" | grep -c "healthy" || echo "0")
    
    if [ "$HEALTHY_COUNT" -eq "0" ]; then
        echo -e "${RED}✗ No healthy targets!${NC}"
        echo "  Vault instances are not responding to health checks"
        echo ""
    else
        echo -e "${GREEN}✓ $HEALTHY_COUNT healthy target(s)${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠ Could not find target group${NC}"
    echo ""
fi

# Check if Vault is actually running on instances
echo -e "${BLUE}Step 4: Checking Vault instances...${NC}"
echo ""

INSTANCE_IDS=$(aws ec2 describe-instances --region us-east-1 \
    --filters "Name=tag:Name,Values=*vault-primary*" "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].InstanceId" --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo -e "${RED}✗ No running Vault instances found${NC}"
    echo ""
else
    echo -e "${GREEN}✓ Found running instances:${NC}"
    for instance in $INSTANCE_IDS; do
        echo "  - $instance"
    done
    echo ""
fi

# Test connectivity
echo -e "${BLUE}Step 5: Testing connectivity...${NC}"
echo ""

echo "Testing Primary LB (https://$PRIMARY_LB_DNS:8200)..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "https://$PRIMARY_LB_DNS:8200/v1/sys/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "000" ]; then
    echo -e "${RED}✗ Connection failed (timeout or refused)${NC}"
    echo "  Possible causes:"
    echo "  1. Load balancer is internal (not internet-facing)"
    echo "  2. Security group blocking port 8200"
    echo "  3. Vault not running on instances"
    echo "  4. Network ACLs blocking traffic"
    echo ""
elif [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "429" ] || [ "$HTTP_CODE" = "473" ] || [ "$HTTP_CODE" = "501" ] || [ "$HTTP_CODE" = "503" ]; then
    echo -e "${GREEN}✓ Connection successful (HTTP $HTTP_CODE)${NC}"
    echo "  Vault is responding!"
    echo ""
    
    # Get detailed status
    VAULT_STATUS=$(curl -k -s "https://$PRIMARY_LB_DNS:8200/v1/sys/health" | jq -r 'if .initialized then "Initialized: \(.initialized), Sealed: \(.sealed)" else "Error getting status" end' 2>/dev/null || echo "Could not parse response")
    echo "  Status: $VAULT_STATUS"
    echo ""
else
    echo -e "${YELLOW}⚠ Unexpected HTTP code: $HTTP_CODE${NC}"
    echo ""
fi

# Check security groups
echo -e "${BLUE}Step 6: Checking security groups...${NC}"
echo ""

if [ -n "$INSTANCE_IDS" ]; then
    FIRST_INSTANCE=$(echo $INSTANCE_IDS | awk '{print $1}')
    SG_IDS=$(aws ec2 describe-instances --region us-east-1 --instance-ids $FIRST_INSTANCE --query "Reservations[0].Instances[0].SecurityGroups[*].GroupId" --output text)
    
    echo "Security Groups attached to Vault instances:"
    for sg in $SG_IDS; do
        echo "  - $sg"
        
        # Check if port 8200 is allowed
        INGRESS_8200=$(aws ec2 describe-security-groups --region us-east-1 --group-ids $sg --query "SecurityGroups[0].IpPermissions[?ToPort==\`8200\`]" --output json)
        
        if [ "$INGRESS_8200" != "[]" ]; then
            echo -e "    ${GREEN}✓ Port 8200 ingress rule exists${NC}"
        else
            echo -e "    ${RED}✗ No port 8200 ingress rule${NC}"
        fi
    done
    echo ""
fi

# Summary
echo "=========================================="
echo "  Diagnostic Summary"
echo "=========================================="
echo ""

if [ "$LB_SCHEME" = "internal" ]; then
    echo -e "${RED}ISSUE FOUND: Load Balancer is INTERNAL${NC}"
    echo ""
    echo "Fix:"
    echo "1. Edit terraform.tfvars"
    echo "2. Set: lb_internal = false"
    echo "3. Run: terraform apply"
    echo ""
elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "${RED}ISSUE FOUND: Cannot connect to Vault${NC}"
    echo ""
    echo "Possible fixes:"
    echo "1. Check if lb_internal = false in terraform.tfvars"
    echo "2. Verify security groups allow port 8200"
    echo "3. Check if Vault service is running on instances"
    echo "4. Review CloudWatch logs for errors"
    echo ""
elif [ "$HEALTHY_COUNT" -eq "0" ]; then
    echo -e "${RED}ISSUE FOUND: No healthy targets${NC}"
    echo ""
    echo "Possible fixes:"
    echo "1. SSH to instances and check: sudo systemctl status vault"
    echo "2. Check Vault logs: sudo journalctl -u vault -f"
    echo "3. Verify Vault license is valid"
    echo "4. Check AWS KMS permissions for auto-unseal"
    echo ""
else
    echo -e "${GREEN}✓ Everything looks good!${NC}"
    echo ""
    echo "Access Vault UI at:"
    echo "  https://$PRIMARY_LB_DNS:8200/ui"
    echo ""
fi

# Made with Bob
