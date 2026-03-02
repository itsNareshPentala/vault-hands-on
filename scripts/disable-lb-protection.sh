#!/bin/bash
# Script to disable load balancer deletion protection

set -e

echo "Disabling deletion protection on load balancers..."
echo ""

# Primary cluster NLB
echo "1. Disabling protection on Primary NLB (us-east-1)..."
aws elbv2 modify-load-balancer-attributes \
	--load-balancer-arn "arn:aws:elasticloadbalancing:us-east-1:790756194327:loadbalancer/net/vault-primary-vault-nlb/a2adbdb3ef2c0333" \
	--attributes Key=deletion_protection.enabled,Value=false \
	--region us-east-1

echo "✓ Primary NLB protection disabled"
echo ""

# DR cluster NLB
echo "2. Disabling protection on DR NLB (us-east-2)..."
aws elbv2 modify-load-balancer-attributes \
	--load-balancer-arn "arn:aws:elasticloadbalancing:us-east-2:790756194327:loadbalancer/net/vault-dr-vault-nlb/6898fb5c3662a5af" \
	--attributes Key=deletion_protection.enabled,Value=false \
	--region us-east-2

echo "✓ DR NLB protection disabled"
echo ""

echo "=========================================="
echo "✓ Deletion protection disabled on both NLBs"
echo "You can now run: terraform destroy"
echo "=========================================="

# Made with Bob
