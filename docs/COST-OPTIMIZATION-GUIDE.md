# Vault Enterprise on AWS - Cost Optimization Guide

## 📊 Deployment Profiles Comparison

| Profile | Monthly Cost | Use Case | Configuration File |
|---------|-------------|----------|-------------------|
| **Production** | ~$826 | Production workloads with HA | `terraform.tfvars.example` |
| **Demo/POC** | ~$150-200 | Demonstrations, testing | `terraform.tfvars.demo` |
| **Minimal** | ~$80-100 | Learning, concept testing | `terraform.tfvars.minimal` |

---

## 🎯 Quick Start for Demo/POC

### Option 1: Demo Configuration (~$150-200/month)

```bash
# Copy demo configuration
cp terraform.tfvars.demo terraform.tfvars

# Edit with your details
nano terraform.tfvars
# - Add your Vault Enterprise license
# - Change allowed_inbound_cidrs to your IP
# - Update owner/project_name

# Deploy
terraform init
terraform plan
terraform apply
```

**What you get:**
- ✅ 1 Vault node per cluster (Primary + DR)
- ✅ Spot instances (70% cheaper)
- ✅ Smaller instances (t3.small)
- ✅ Single NAT Gateway per region
- ✅ Minimal storage (20GB)
- ✅ AWS KMS auto-unseal
- ✅ DR replication functional
- ✅ Load balancers included
- ❌ No high availability
- ❌ No monitoring/logging

### Option 2: Minimal Configuration (~$80-100/month)

```bash
# Copy minimal configuration
cp terraform.tfvars.minimal terraform.tfvars

# Edit with your details
nano terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply
```

**What you get:**
- ✅ 1 Vault node per cluster
- ✅ Spot instances (t3.micro - FREE TIER!)
- ✅ Same region deployment (no data transfer)
- ✅ Single NAT Gateway total
- ✅ Minimal storage (10GB)
- ✅ AWS KMS auto-unseal
- ✅ DR replication functional
- ❌ No load balancers (direct access)
- ❌ No HA, no monitoring

---

## 💰 Detailed Cost Breakdown

### Production Configuration (~$826/month)

| Component | Quantity | Unit Cost | Monthly Cost |
|-----------|----------|-----------|--------------|
| **EC2 Instances** |
| Vault nodes (t3.large) | 6 | $0.0832/hr | $364.42 |
| Load balancers (t3.medium) | 2 | $0.0416/hr | $60.74 |
| **Storage** |
| EBS volumes (100GB gp3) | 6 | $8/volume | $48.00 |
| **Networking** |
| NAT Gateways | 6 | $0.045/hr | $197.10 |
| NAT data processing | - | - | $65.70 |
| Network Load Balancers | 2 | $0.0225/hr | $32.85 |
| VPC Peering data transfer | - | - | $20.00 |
| **Security** |
| AWS KMS keys | 2 | $1/key | $2.00 |
| **Monitoring** |
| CloudWatch Logs/Metrics | - | - | $15.00 |
| VPC Flow Logs | - | - | $20.00 |
| **TOTAL** | | | **$825.81** |

### Demo Configuration (~$150-200/month)

| Component | Quantity | Unit Cost | Monthly Cost | Savings |
|-----------|----------|-----------|--------------|---------|
| **EC2 Instances (Spot)** |
| Vault nodes (t3.small spot) | 2 | $0.0062/hr | $9.05 | -$355 |
| Load balancers (t3.micro) | 2 | $0.0104/hr | $15.18 | -$45 |
| **Storage** |
| EBS volumes (20GB gp3) | 2 | $1.60/volume | $3.20 | -$45 |
| **Networking** |
| NAT Gateways | 2 | $0.045/hr | $65.70 | -$197 |
| NAT data processing | - | - | $20.00 | -$46 |
| Network Load Balancers | 2 | $0.0225/hr | $32.85 | $0 |
| VPC Peering (same region) | - | - | $5.00 | -$15 |
| **Security** |
| AWS KMS keys | 2 | $1/key | $2.00 | $0 |
| **Monitoring** |
| CloudWatch (disabled) | - | - | $0.00 | -$35 |
| **TOTAL** | | | **~$153** | **-$673** |

### Minimal Configuration (~$80-100/month)

| Component | Quantity | Unit Cost | Monthly Cost | Savings |
|-----------|----------|-----------|--------------|---------|
| **EC2 Instances (Spot)** |
| Vault nodes (t3.micro spot) | 2 | $0.0031/hr | $4.53 | -$360 |
| Load balancers | 0 | - | $0.00 | -$76 |
| **Storage** |
| EBS volumes (10GB gp3) | 2 | $0.80/volume | $1.60 | -$46 |
| **Networking** |
| NAT Gateway | 1 | $0.045/hr | $32.85 | -$230 |
| NAT data processing | - | - | $10.00 | -$56 |
| Network Load Balancers | 0 | - | $0.00 | -$33 |
| VPC Peering (same region) | - | - | $2.00 | -$18 |
| **Security** |
| AWS KMS keys | 2 | $1/key | $2.00 | $0 |
| **Monitoring** |
| CloudWatch (disabled) | - | - | $0.00 | -$35 |
| **TOTAL** | | | **~$53** | **-$773** |

**Note:** Minimal config actual cost may be $80-100 due to data transfer and other variable costs.

---

## 🔧 Cost Optimization Strategies

### 1. Use Spot Instances (70% Savings)

**Production:**
```hcl
# Use Spot for DR cluster only
dr_instance_market_type = "spot"
dr_spot_price          = "0.025"  # t3.small max price
```

**Demo/Minimal:**
```hcl
# Use Spot for everything
vault_instance_market_type = "spot"
vault_spot_price          = "0.025"
```

**Savings:** ~$255/month (70% off EC2 costs)

### 2. Reduce NAT Gateways (21% Savings)

**Current:** 3 NAT Gateways per region = 6 total = $263/month

**Optimized:**
```hcl
single_nat_gateway = true  # 1 per region = 2 total
```

**Savings:** ~$175/month

**Ultra-optimized (Demo only):**
```hcl
# Same region deployment = 1 NAT Gateway total
primary_region = "us-east-1"
dr_region      = "us-east-1"
single_nat_gateway = true
```

**Savings:** ~$230/month

### 3. Use Smaller Instance Types

| Instance Type | vCPU | RAM | Cost/hr | Monthly | Use Case |
|---------------|------|-----|---------|---------|----------|
| t3.large | 2 | 8GB | $0.0832 | $60.74 | Production |
| t3.medium | 2 | 4GB | $0.0416 | $30.37 | Light production |
| t3.small | 2 | 2GB | $0.0208 | $15.18 | Demo/POC |
| t3.micro | 2 | 1GB | $0.0104 | $7.59 | Minimal/testing |

**Demo:**
```hcl
vault_instance_type = "t3.small"  # Save $45/node
```

**Minimal:**
```hcl
vault_instance_type = "t3.micro"  # Save $53/node (FREE TIER!)
```

### 4. Reduce Storage Size

**Production:** 100GB per node = $48/month

**Demo:**
```hcl
vault_data_volume_size = 20  # Save $38/month
```

**Minimal:**
```hcl
vault_data_volume_size = 10  # Save $46/month
```

### 5. Disable Load Balancers (Demo Only)

**Production:** 2 NLBs = $33/month

**Minimal:**
```hcl
enable_load_balancer = false  # Access nodes directly
```

**Savings:** $33/month

**Access pattern:**
```bash
# Instead of: https://load-balancer-ip:8200
# Use: https://vault-node-ip:8200
```

### 6. Disable Monitoring (Demo Only)

**Production:** CloudWatch + VPC Flow Logs = $35/month

**Demo/Minimal:**
```hcl
enable_cloudwatch_logs    = false
enable_detailed_monitoring = false
enable_vpc_flow_logs      = false
```

**Savings:** $35/month

### 7. Same Region Deployment (Demo Only)

**Production:** Multi-region for true DR

**Demo:**
```hcl
primary_region = "us-east-1"
dr_region      = "us-east-1"  # Same region
```

**Savings:** ~$15/month (data transfer)

**Note:** This is NOT true disaster recovery but demonstrates DR replication functionality.

### 8. Use Reserved Instances (Long-term)

**1-Year Commitment:**
- Standard Reserved: 40% savings
- Convertible Reserved: 31% savings

**3-Year Commitment:**
- Standard Reserved: 60% savings
- Convertible Reserved: 54% savings

**Example:**
```bash
# Production with 1-year Reserved Instances
# Current: $826/month
# With Reserved: ~$496/month (40% savings)
```

### 9. Auto-Shutdown for Non-Production

**Demo/Minimal only:**

Create Lambda function to stop instances during off-hours:

```bash
# Stop instances at 6 PM weekdays
# Start instances at 8 AM weekdays
# Keep stopped on weekends

# Savings: ~60% of compute costs
# Demo: $153 → $92/month
# Minimal: $80 → $48/month
```

### 10. Use AWS Free Tier (First 12 Months)

**Eligible resources:**
- 750 hours/month of t3.micro (covers 1 instance 24/7)
- 30GB EBS storage
- 1GB data transfer out

**Minimal config can leverage:**
- 2x t3.micro instances (use 1 free, pay for 1)
- 20GB EBS (10GB free)

**Effective cost with Free Tier:** ~$40-50/month

---

## 📋 Deployment Comparison Matrix

| Feature | Production | Demo | Minimal |
|---------|-----------|------|---------|
| **Cost** | $826/mo | $150-200/mo | $80-100/mo |
| **Vault Nodes** | 6 (3+3) | 2 (1+1) | 2 (1+1) |
| **Instance Type** | t3.large | t3.small | t3.micro |
| **Instance Market** | On-Demand | Spot | Spot |
| **Storage per Node** | 100GB | 20GB | 10GB |
| **Load Balancers** | Yes (2) | Yes (2) | No |
| **NAT Gateways** | 6 | 2 | 1 |
| **Regions** | Multi-region | Multi-region | Same region |
| **High Availability** | Yes | No | No |
| **Auto-Unseal** | Yes | Yes | Yes |
| **DR Replication** | Yes | Yes | Yes |
| **Monitoring** | Full | Disabled | Disabled |
| **Backups** | Automated | Disabled | Disabled |
| **Use Case** | Production | Demo/POC | Learning |

---

## 🚀 Quick Deployment Commands

### Deploy Demo Configuration

```bash
# 1. Copy demo config
cp terraform.tfvars.demo terraform.tfvars

# 2. Edit configuration
nano terraform.tfvars
# - Add Vault license
# - Update allowed_inbound_cidrs
# - Set owner/project_name

# 3. Deploy
terraform init
terraform plan -out=demo.tfplan
terraform apply demo.tfplan

# Estimated time: 15-20 minutes
# Estimated cost: ~$150-200/month
```

### Deploy Minimal Configuration

```bash
# 1. Copy minimal config
cp terraform.tfvars.minimal terraform.tfvars

# 2. Edit configuration
nano terraform.tfvars

# 3. Deploy
terraform init
terraform plan -out=minimal.tfplan
terraform apply minimal.tfplan

# Estimated time: 10-15 minutes
# Estimated cost: ~$80-100/month
```

### Upgrade from Demo to Production

```bash
# 1. Backup current state
terraform state pull > terraform.tfstate.backup

# 2. Update configuration
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# - Increase vault_node_count to 3
# - Change instance_type to t3.large
# - Set vault_instance_market_type to "on-demand"
# - Set single_nat_gateway to false
# - Enable monitoring

# 3. Plan upgrade
terraform plan

# 4. Apply (will recreate resources)
terraform apply
```

---

## ⚠️ Important Notes

### Demo/Minimal Limitations

**NOT suitable for:**
- ❌ Production workloads
- ❌ Sensitive data
- ❌ High availability requirements
- ❌ Performance testing
- ❌ Compliance requirements

**Suitable for:**
- ✅ Learning Vault concepts
- ✅ Testing DR replication
- ✅ Demonstrations
- ✅ POC presentations
- ✅ Development/testing

### Spot Instance Considerations

**Pros:**
- 70% cost savings
- Same performance as On-Demand

**Cons:**
- Can be interrupted with 2-minute warning
- Not suitable for production Primary cluster
- OK for DR cluster (can failover)
- OK for demo/testing

**Best Practice:**
```hcl
# Production: Use Spot for DR only
primary_instance_market_type = "on-demand"
dr_instance_market_type      = "spot"

# Demo: Use Spot for everything
vault_instance_market_type = "spot"
```

### Free Tier Optimization

**AWS Free Tier (first 12 months):**
- 750 hours/month t2.micro or t3.micro
- 30GB EBS storage
- 15GB data transfer out

**Minimal config optimization:**
```hcl
# Use t3.micro to leverage free tier
vault_instance_type = "t3.micro"

# Reduce storage to fit free tier
vault_data_volume_size = 10  # 20GB total (10GB free)

# Deploy in same region to minimize data transfer
primary_region = "us-east-1"
dr_region      = "us-east-1"
```

**Effective cost with Free Tier:** ~$40-50/month

---

## 📊 Cost Optimization Summary

| Optimization | Production | Demo | Minimal | Savings |
|--------------|-----------|------|---------|---------|
| **Baseline** | $826 | $826 | $826 | - |
| Use Spot Instances | $571 | $153 | $53 | 31-94% |
| Reduce NAT Gateways | $651 | $153 | $53 | 21% |
| Smaller Instances | - | $153 | $53 | - |
| Disable Load Balancers | - | - | $53 | 4% |
| Disable Monitoring | - | $153 | $53 | 4% |
| Same Region | - | $153 | $53 | 2% |
| **TOTAL SAVINGS** | - | **81%** | **94%** | - |

---

## 🎯 Recommendations

### For Production:
1. Start with full configuration ($826/month)
2. Use Spot for DR cluster only ($571/month)
3. After 1 month, purchase Reserved Instances ($343/month)
4. **Final cost: ~$343/month (58% savings)**

### For Demo/POC:
1. Use `terraform.tfvars.demo` configuration
2. Deploy with Spot instances
3. Same region deployment acceptable
4. **Cost: ~$150-200/month (81% savings)**

### For Learning/Testing:
1. Use `terraform.tfvars.minimal` configuration
2. Leverage AWS Free Tier if available
3. Consider auto-shutdown during off-hours
4. **Cost: ~$40-80/month (90-95% savings)**

---

## 📞 Support

For questions about cost optimization:
1. Review this guide
2. Check AWS Cost Explorer for actual usage
3. Use AWS Cost Calculator for estimates
4. Consider AWS Savings Plans for long-term deployments

---

**Remember:** Always `terraform destroy` when done with demo/testing to avoid unnecessary costs!

```bash
# Clean up resources
terraform destroy -auto-approve

# Verify cleanup
terraform state list  # Should be empty