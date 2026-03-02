# Final Deployment Checklist - Vault Enterprise on AWS

## ✅ Configuration Review Complete

### Issues Found and Fixed

1. **NAT Gateway Dependency Issue** ✅ FIXED
   - **Problem**: EC2 instances launched before NAT Gateways were ready
   - **Fix**: Added `depends_on` in `modules/vault-cluster/main.tf` line 728-732
   - **Impact**: Instances will now wait for NAT Gateways before launching

2. **Load Balancer Configuration** ✅ CORRECT
   - `lb_internal = false` (internet-facing) - Line 88 in terraform.tfvars
   - Deletion protection enabled for safety

3. **Network Configuration** ✅ CORRECT
   - VPC CIDR: Primary 10.0.0.0/16, DR 10.1.0.0/16
   - 3 Availability Zones per region
   - NAT Gateways: 3 per region (one per AZ)
   - Private subnets for instances
   - Public subnets for NAT Gateways and Load Balancers

4. **Security Configuration** ✅ CORRECT
   - AWS KMS auto-unseal enabled
   - EBS encryption enabled
   - IMDSv2 required
   - Proper security groups configured

## Current State

### Infrastructure Status
- ❌ Instances have failed user-data (no internet during initial boot)
- ✅ NAT Gateways are now operational
- ✅ Load balancers are configured
- ✅ All networking is in place

### What Needs to Happen

**Option 1: Destroy and Redeploy (RECOMMENDED)**
```bash
# 1. Destroy everything
./destroy-all.sh

# 2. Wait for complete destruction (~15 minutes)

# 3. Redeploy with fixed configuration
terraform init
terraform plan
terraform apply

# 4. Wait for deployment (~20 minutes)
# 5. Wait for Vault installation (~10 minutes)
# 6. Verify with diagnostics
./diagnose-vault-access.sh
```

**Option 2: Recreate Only Instances**
```bash
# 1. Recreate instances only (keeps networking)
./recreate-instances-only.sh

# 2. Wait for new instances (~5 minutes)
# 3. Wait for Vault installation (~10 minutes)
# 4. Verify with diagnostics
./diagnose-vault-access.sh
```

## Configuration Files Status

### ✅ Correct Files
- `modules/vault-cluster/main.tf` - NAT Gateway dependency added
- `terraform.tfvars` - All settings correct
- `main.tf` - Root module correct
- `versions.tf` - Provider versions correct
- `modules/vault-cluster/versions.tf` - Module versions correct

### 📝 Helper Scripts Available
- `destroy-all.sh` - Complete infrastructure destruction
- `recreate-instances-only.sh` - Recreate only EC2 instances
- `diagnose-vault-access.sh` - Comprehensive diagnostics
- `check-vault-instances.sh` - Check Vault installation status
- `fix-nat-gateway.sh` - NAT Gateway diagnostics

## Expected Behavior After Fix

### During Deployment
1. VPC and networking created (~2 min)
2. NAT Gateways created and become "available" (~3 min)
3. Route tables configured with NAT routes (~1 min)
4. **EC2 instances wait for NAT Gateways** (new behavior)
5. EC2 instances launch with internet access (~2 min)
6. User-data runs successfully (~5-10 min):
   - System updates
   - Package installation (awscli, jq, unzip)
   - Vault binary download
   - Vault configuration
   - Vault service start
7. Load balancer health checks pass (~2 min)
8. Vault UI becomes accessible

### Timeline
- **Infrastructure deployment**: ~10 minutes
- **Vault installation**: ~10 minutes
- **Total**: ~20 minutes

### Verification Steps
```bash
# 1. Check instance health
./check-vault-instances.sh

# 2. Check load balancer targets
./diagnose-vault-access.sh

# 3. Get Vault UI URLs
terraform output primary_cluster_lb_dns
terraform output dr_cluster_lb_dns

# 4. Access Vault UI
https://<lb-dns>:8200/ui
```

## Cost Estimate

### Monthly Costs (Both Clusters)
- **EC2 Instances**: 6 × t3.xlarge = ~$450/month
- **NAT Gateways**: 6 × $32 = ~$192/month
- **Load Balancers**: 2 × NLB = ~$32/month
- **EBS Volumes**: ~$50/month
- **Data Transfer**: ~$50/month
- **KMS**: ~$2/month
- **Total**: ~$776/month

### Hourly Cost
- ~$1.08/hour for both clusters running

## Security Notes

1. **Vault License**: Valid enterprise license configured
2. **Auto-Unseal**: AWS KMS configured for both regions
3. **Network Access**: 
   - Instances in private subnets
   - Access via internet-facing NLB
   - No direct SSH access (use AWS SSM)
4. **Encryption**: 
   - EBS volumes encrypted
   - KMS keys with rotation enabled
5. **IAM**: Least privilege roles configured

## Troubleshooting

### If Deployment Fails

1. **Check Terraform State**
   ```bash
   terraform state list
   terraform show
   ```

2. **Check AWS Console**
   - EC2 instances status
   - NAT Gateway status
   - Load balancer target health
   - CloudWatch logs

3. **Check Instance Logs**
   ```bash
   aws ssm start-session --target <instance-id> --region us-east-1
   sudo cat /var/log/user-data.log
   sudo systemctl status vault
   ```

4. **Common Issues**
   - NAT Gateway still pending: Wait 2-3 minutes
   - Targets unhealthy: Check user-data logs
   - Can't access UI: Check security groups and NLB configuration

## Next Steps

1. **Choose deployment option** (destroy & redeploy OR recreate instances)
2. **Run the appropriate script**
3. **Wait for completion** (~20 minutes for full deployment)
4. **Verify with diagnostics**
5. **Access Vault UI**
6. **Initialize Vault** (first time only)
7. **Configure DR replication** (if needed)

## Support

If issues persist:
1. Check CloudWatch logs for detailed errors
2. Review user-data logs on instances
3. Verify AWS service quotas
4. Check IAM permissions
5. Ensure Vault license is valid

---

**Configuration is now correct and ready for deployment!**

The key fix was adding the `depends_on` block to ensure instances wait for NAT Gateways to be ready before launching. This will prevent the user-data failures you experienced.