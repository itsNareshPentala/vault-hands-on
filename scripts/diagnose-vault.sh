#!/bin/bash
# Vault Deployment Diagnostic Script

set -e

echo "=========================================="
echo "Vault Deployment Diagnostics"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REGION="us-east-1"
LB_ARN="arn:aws:elasticloadbalancing:us-east-1:790756194327:loadbalancer/net/vault-primary-vault-nlb/a2adbdb3ef2c0333"
INSTANCE_IDS=("i-009b993d31da4cee2" "i-008b427db31cbda44" "i-068288e04b77112c3")

echo "1. Checking NLB Target Groups..."
echo "----------------------------------------"
TG_ARN=$(aws elbv2 describe-target-groups \
	--load-balancer-arn "$LB_ARN" \
	--region "$REGION" \
	--query 'TargetGroups[0].TargetGroupArn' \
	--output text 2>/dev/null || echo "ERROR")

if [ "$TG_ARN" = "ERROR" ]; then
	echo -e "${RED}✗ Failed to get target group${NC}"
else
	echo -e "${GREEN}✓ Target Group: $TG_ARN${NC}"

	echo ""
	echo "2. Checking Target Health..."
	echo "----------------------------------------"
	aws elbv2 describe-target-health \
		--target-group-arn "$TG_ARN" \
		--region "$REGION" \
		--output table
fi

echo ""
echo "3. Checking Instance Status..."
echo "----------------------------------------"
aws ec2 describe-instance-status \
	--instance-ids "${INSTANCE_IDS[@]}" \
	--region "$REGION" \
	--query 'InstanceStatuses[*].[InstanceId,InstanceState.Name,InstanceStatus.Status,SystemStatus.Status]' \
	--output table

echo ""
echo "4. Checking Security Group Rules..."
echo "----------------------------------------"
echo "Load Balancer Security Group (sg-0b9d4e311a1b088ab):"
aws ec2 describe-security-groups \
	--group-ids sg-0b9d4e311a1b088ab \
	--region "$REGION" \
	--query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
	--output table

echo ""
echo "Vault Instance Security Group (sg-05bd3addbc0be5855):"
aws ec2 describe-security-groups \
	--group-ids sg-05bd3addbc0be5855 \
	--region "$REGION" \
	--query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,UserIdGroupPairs[0].GroupId]' \
	--output table

echo ""
echo "5. Testing Network Connectivity..."
echo "----------------------------------------"
echo "Testing NLB endpoint..."
timeout 5 curl -k -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
	https://vault-primary-vault-nlb-a2adbdb3ef2c0333.elb.us-east-1.amazonaws.com:8200/v1/sys/health ||
	echo -e "${RED}✗ Connection failed or timed out${NC}"

echo ""
echo "6. Checking CloudWatch Logs (if enabled)..."
echo "----------------------------------------"
LOG_GROUP="/aws/vault/vault-primary"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" &>/dev/null; then
	echo "Recent log streams:"
	aws logs describe-log-streams \
		--log-group-name "$LOG_GROUP" \
		--region "$REGION" \
		--order-by LastEventTime \
		--descending \
		--max-items 3 \
		--query 'logStreams[*].[logStreamName,lastEventTime]' \
		--output table
else
	echo -e "${YELLOW}⚠ CloudWatch logs not enabled${NC}"
fi

echo ""
echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""
echo "Common Issues:"
echo "1. Vault service not started - Check user-data script execution"
echo "2. Target health check failing - Vault not listening on port 8200"
echo "3. Security group misconfiguration - Check NLB -> Vault connectivity"
echo "4. Vault not initialized - Service may be sealed"
echo ""
echo "Next Steps:"
echo "- Use AWS Systems Manager Session Manager to connect to instance"
echo "- Check: sudo systemctl status vault"
echo "- Check: sudo journalctl -u vault -n 100"
echo "- Check: /var/log/cloud-init-output.log"

# Made with Bob
