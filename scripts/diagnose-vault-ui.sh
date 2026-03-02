#!/bin/bash
# Diagnose Vault UI connectivity issues

set -e

echo "=== Vault UI Connectivity Diagnostics ==="
echo ""

# Check if terraform.tfvars.demo exists
if [ ! -f "terraform.tfvars.demo" ]; then
	echo "ERROR: terraform.tfvars.demo not found"
	exit 1
fi

# Get the load balancer DNS from Terraform output
echo "1. Getting Load Balancer DNS..."
PRIMARY_LB_DNS=$(terraform output -raw primary_cluster_lb_dns 2>/dev/null || echo "")
DR_LB_DNS=$(terraform output -raw dr_cluster_lb_dns 2>/dev/null || echo "")

if [ -z "$PRIMARY_LB_DNS" ]; then
	echo "ERROR: Could not get primary load balancer DNS from Terraform output"
	echo "Run: terraform output"
	exit 1
fi

echo "Primary LB DNS: $PRIMARY_LB_DNS"
echo "DR LB DNS: $DR_LB_DNS"
echo ""

# Get primary cluster region
PRIMARY_REGION=$(grep '^primary_region' terraform.tfvars.demo | awk -F'"' '{print $2}')
echo "Primary Region: $PRIMARY_REGION"
echo ""

# Check Load Balancer status
echo "2. Checking Load Balancer status..."
LB_ARN=$(aws elbv2 describe-load-balancers --region "$PRIMARY_REGION" \
	--query "LoadBalancers[?DNSName=='$PRIMARY_LB_DNS'].LoadBalancerArn" \
	--output text 2>/dev/null || echo "")

if [ -z "$LB_ARN" ]; then
	echo "ERROR: Load balancer not found"
	exit 1
fi

LB_STATE=$(aws elbv2 describe-load-balancers --region "$PRIMARY_REGION" \
	--load-balancer-arns "$LB_ARN" \
	--query 'LoadBalancers[0].State.Code' --output text)

echo "Load Balancer State: $LB_STATE"

if [ "$LB_STATE" != "active" ]; then
	echo "WARNING: Load balancer is not active"
fi
echo ""

# Check Target Group health
echo "3. Checking Target Group health..."
TG_ARN=$(aws elbv2 describe-target-groups --region "$PRIMARY_REGION" \
	--load-balancer-arn "$LB_ARN" \
	--query 'TargetGroups[0].TargetGroupArn' --output text)

echo "Target Group ARN: $TG_ARN"

TARGET_HEALTH=$(aws elbv2 describe-target-health --region "$PRIMARY_REGION" \
	--target-group-arn "$TG_ARN" --output json)

echo "Target Health Status:"
echo "$TARGET_HEALTH" | jq -r '.TargetHealthDescriptions[] | "  Instance: \(.Target.Id) - State: \(.TargetHealth.State) - Reason: \(.TargetHealth.Reason // "N/A")"'

HEALTHY_COUNT=$(echo "$TARGET_HEALTH" | jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length')
TOTAL_COUNT=$(echo "$TARGET_HEALTH" | jq '.TargetHealthDescriptions | length')

echo ""
echo "Healthy targets: $HEALTHY_COUNT / $TOTAL_COUNT"

if [ "$HEALTHY_COUNT" -eq 0 ]; then
	echo "ERROR: No healthy targets. Vault instances may not be running or responding."
fi
echo ""

# Check Security Group rules
echo "4. Checking Security Group rules..."
INSTANCE_ID=$(echo "$TARGET_HEALTH" | jq -r '.TargetHealthDescriptions[0].Target.Id')

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
	SG_ID=$(aws ec2 describe-instances --region "$PRIMARY_REGION" \
		--instance-ids "$INSTANCE_ID" \
		--query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
		--output text)

	echo "Instance Security Group: $SG_ID"

	echo "Inbound rules for port 8200:"
	aws ec2 describe-security-groups --region "$PRIMARY_REGION" \
		--group-ids "$SG_ID" \
		--query 'SecurityGroups[0].IpPermissions[?ToPort==`8200`]' \
		--output json | jq -r '.[] | "  Protocol: \(.IpProtocol) Port: \(.FromPort)-\(.ToPort) Source: \(.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId)"'
fi
echo ""

# Test connectivity to Load Balancer
echo "5. Testing connectivity to Load Balancer..."
echo "Testing HTTPS connection to $PRIMARY_LB_DNS:8200..."

# Test with curl (ignore cert validation)
CURL_OUTPUT=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "https://$PRIMARY_LB_DNS:8200/v1/sys/health" 2>&1 || echo "000")

echo "HTTP Status Code: $CURL_OUTPUT"

if [ "$CURL_OUTPUT" = "000" ]; then
	echo "ERROR: Cannot connect to load balancer"
	echo "Possible issues:"
	echo "  - Load balancer not accepting connections"
	echo "  - Security group blocking traffic"
	echo "  - Vault not running on instances"
elif [ "$CURL_OUTPUT" = "501" ] || [ "$CURL_OUTPUT" = "503" ]; then
	echo "WARNING: Vault is sealed or not initialized"
	echo "This is normal for a new installation"
elif [ "$CURL_OUTPUT" = "200" ] || [ "$CURL_OUTPUT" = "429" ] || [ "$CURL_OUTPUT" = "473" ]; then
	echo "SUCCESS: Vault is responding"
else
	echo "Unexpected status code: $CURL_OUTPUT"
fi
echo ""

# Check if Vault is running on instances
echo "6. Checking Vault service status on instances..."
if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
	echo "Checking instance: $INSTANCE_ID"

	# Try to get Vault status via SSM
	VAULT_STATUS=$(aws ssm send-command \
		--region "$PRIMARY_REGION" \
		--instance-ids "$INSTANCE_ID" \
		--document-name "AWS-RunShellScript" \
		--parameters 'commands=["systemctl is-active vault","vault status 2>&1 || true"]' \
		--output text --query 'Command.CommandId' 2>/dev/null || echo "")

	if [ -n "$VAULT_STATUS" ]; then
		echo "SSM Command ID: $VAULT_STATUS"
		echo "Wait 5 seconds for command to execute..."
		sleep 5

		aws ssm get-command-invocation \
			--region "$PRIMARY_REGION" \
			--command-id "$VAULT_STATUS" \
			--instance-id "$INSTANCE_ID" \
			--query 'StandardOutputContent' \
			--output text 2>/dev/null || echo "Could not retrieve command output"
	else
		echo "Could not execute SSM command. Check SSM agent status."
	fi
fi
echo ""

# Summary and recommendations
echo "=== Summary ==="
echo ""
echo "Vault UI URL: https://$PRIMARY_LB_DNS:8200/ui"
echo ""

if [ "$HEALTHY_COUNT" -eq 0 ]; then
	echo "❌ ISSUE: No healthy targets in load balancer"
	echo ""
	echo "Troubleshooting steps:"
	echo "1. Check if Vault is running: sudo systemctl status vault"
	echo "2. Check Vault logs: sudo journalctl -u vault -n 50"
	echo "3. Verify Vault is listening on port 8200: sudo netstat -tlnp | grep 8200"
	echo "4. Check if TLS certificates exist: ls -la /opt/vault/tls/"
	echo "5. Verify security group allows traffic from load balancer"
elif [ "$CURL_OUTPUT" = "501" ] || [ "$CURL_OUTPUT" = "503" ]; then
	echo "⚠️  Vault is sealed or not initialized"
	echo ""
	echo "Next steps:"
	echo "1. SSH/SSM into a Vault instance"
	echo "2. Initialize Vault: vault operator init -recovery-shares=5 -recovery-threshold=3"
	echo "3. Access UI at: https://$PRIMARY_LB_DNS:8200/ui"
	echo "4. Use the root token from initialization to log in"
elif [ "$CURL_OUTPUT" = "200" ] || [ "$CURL_OUTPUT" = "429" ] || [ "$CURL_OUTPUT" = "473" ]; then
	echo "✅ Vault is accessible and responding"
	echo ""
	echo "Access the UI at: https://$PRIMARY_LB_DNS:8200/ui"
	echo ""
	echo "Note: You may see a certificate warning in your browser."
	echo "This is expected with self-signed certificates. Click 'Advanced' and proceed."
else
	echo "❓ Unexpected state. Review the diagnostics above."
fi

# Made with Bob
