#!/bin/bash

echo "=========================================="
echo "  Complete Infrastructure Destruction"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will destroy ALL resources including:"
echo "  - 6 EC2 instances (Primary + DR)"
echo "  - 2 Network Load Balancers"
echo "  - 2 VPCs with all networking"
echo "  - 6 NAT Gateways"
echo "  - 2 KMS keys"
echo "  - All security groups, IAM roles, etc."
echo ""
read -p "Are you absolutely sure? Type 'destroy' to confirm: " confirm

if [ "$confirm" != "destroy" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 1: Disabling deletion protection on load balancers..."
echo "------------------------------------------------------------"

# Get Primary LB ARN
PRIMARY_LB_ARN=$(aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'vault-primary')].LoadBalancerArn" \
  --output text)

if [ -n "$PRIMARY_LB_ARN" ]; then
    echo "Disabling protection on Primary LB: $PRIMARY_LB_ARN"
    aws elbv2 modify-load-balancer-attributes \
      --region us-east-1 \
      --load-balancer-arn "$PRIMARY_LB_ARN" \
      --attributes Key=deletion_protection.enabled,Value=false
fi

# Get DR LB ARN
DR_LB_ARN=$(aws elbv2 describe-load-balancers --region us-east-2 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'vault-dr')].LoadBalancerArn" \
  --output text)

if [ -n "$DR_LB_ARN" ]; then
    echo "Disabling protection on DR LB: $DR_LB_ARN"
    aws elbv2 modify-load-balancer-attributes \
      --region us-east-2 \
      --load-balancer-arn "$DR_LB_ARN" \
      --attributes Key=deletion_protection.enabled,Value=false
fi

echo ""
echo "Step 2: Running terraform destroy..."
echo "------------------------------------------------------------"
echo ""

terraform destroy

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "  ✅ Destruction Complete"
    echo "=========================================="
    echo ""
    echo "All infrastructure has been destroyed."
    echo ""
else
    echo ""
    echo "❌ Terraform destroy encountered errors."
    echo ""
    echo "Common issues and fixes:"
    echo ""
    echo "1. If NAT Gateway EIPs are still attached:"
    echo "   Wait 2-3 minutes and run: terraform destroy"
    echo ""
    echo "2. If Internet Gateway has dependencies:"
    echo "   Wait for NAT Gateways to fully delete, then run: terraform destroy"
    echo ""
    echo "3. If resources are stuck:"
    echo "   Check AWS console and manually delete stuck resources"
    echo ""
    exit 1
fi
