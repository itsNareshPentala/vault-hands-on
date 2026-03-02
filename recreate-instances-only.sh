#!/bin/bash

echo "=========================================="
echo "  Recreating ONLY Vault Instances"
echo "=========================================="
echo ""

echo "This will recreate only the EC2 instances, leaving all other infrastructure intact."
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 1: Destroying Primary Cluster Instances..."
echo "------------------------------------------------------------"

terraform destroy -target='module.primary_cluster.aws_instance.vault[0]' -auto-approve
terraform destroy -target='module.primary_cluster.aws_instance.vault[1]' -auto-approve
terraform destroy -target='module.primary_cluster.aws_instance.vault[2]' -auto-approve

echo ""
echo "Step 2: Destroying DR Cluster Instances..."
echo "------------------------------------------------------------"

terraform destroy -target='module.dr_cluster.aws_instance.vault[0]' -auto-approve
terraform destroy -target='module.dr_cluster.aws_instance.vault[1]' -auto-approve
terraform destroy -target='module.dr_cluster.aws_instance.vault[2]' -auto-approve

echo ""
echo "Step 3: Recreating instances with fixed configuration..."
echo "------------------------------------------------------------"
echo ""
echo "This will create 6 new instances that will wait for NAT Gateways to be ready."
echo ""

terraform apply -target='module.primary_cluster.aws_instance.vault' -target='module.dr_cluster.aws_instance.vault' -auto-approve

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "  Instance Recreation Complete"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Wait 10 minutes for user-data to complete"
    echo ""
    echo "2. Check if Vault is installed:"
    echo "   ./check-vault-instances.sh"
    echo ""
    echo "3. Run diagnostics to verify health:"
    echo "   ./diagnose-vault-access.sh"
    echo ""
    echo "4. Get load balancer URLs:"
    echo "   terraform output primary_cluster_lb_dns"
    echo "   terraform output dr_cluster_lb_dns"
    echo ""
else
    echo ""
    echo "❌ Terraform apply failed. Please check the errors above."
    exit 1
fi
