#!/bin/bash

echo "=========================================="
echo "  Recreating Vault Instances"
echo "=========================================="
echo ""

echo "This will recreate all Vault instances so user-data can run with working internet."
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 1: Tainting Primary Cluster Instances..."
echo "------------------------------------------------------------"

terraform taint 'module.primary_cluster.aws_instance.vault[0]'
terraform taint 'module.primary_cluster.aws_instance.vault[1]'
terraform taint 'module.primary_cluster.aws_instance.vault[2]'

echo ""
echo "Step 2: Tainting DR Cluster Instances..."
echo "------------------------------------------------------------"

terraform taint 'module.dr_cluster.aws_instance.vault[0]'
terraform taint 'module.dr_cluster.aws_instance.vault[1]'
terraform taint 'module.dr_cluster.aws_instance.vault[2]'

echo ""
echo "Step 3: Applying changes to recreate instances..."
echo "------------------------------------------------------------"
echo ""
echo "This will:"
echo "  - Destroy the 6 existing instances"
echo "  - Create 6 new instances"
echo "  - Run user-data with working internet connectivity"
echo "  - Install Vault on all instances"
echo ""
echo "Expected time: 5-10 minutes"
echo ""

terraform apply

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "  Instance Recreation Complete"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Wait 5-10 minutes for user-data to complete"
    echo ""
    echo "2. Check if Vault is installed on an instance:"
    echo "   aws ssm start-session --region us-east-1 --target <INSTANCE_ID>"
    echo "   sudo systemctl status vault"
    echo "   vault version"
    echo ""
    echo "3. Run diagnostics to verify health:"
    echo "   ./diagnose-vault-access.sh"
    echo ""
    echo "4. Access Vault UI:"
    
    # Get load balancer DNS names safely
    PRIMARY_LB=$(terraform output -raw primary_cluster_lb_dns 2>/dev/null)
    DR_LB=$(terraform output -raw dr_cluster_lb_dns 2>/dev/null)
    
    if [ -n "$PRIMARY_LB" ]; then
        echo "   Primary: https://${PRIMARY_LB}:8200/ui"
    else
        echo "   Primary: Run 'terraform output primary_cluster_lb_dns' to get URL"
    fi
    
    if [ -n "$DR_LB" ]; then
        echo "   DR:      https://${DR_LB}:8200/ui"
    else
        echo "   DR:      Run 'terraform output dr_cluster_lb_dns' to get URL"
    fi
    echo ""
else
    echo ""
    echo "❌ Terraform apply failed. Please check the errors above."
    exit 1
fi

# Made with Bob
