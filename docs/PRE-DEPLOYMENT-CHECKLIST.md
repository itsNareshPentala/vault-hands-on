# Pre-Deployment Checklist

## ✅ Before Running `terraform init` and `terraform apply`

### 1. **AWS Prerequisites**

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI configured (optional, for verification)
  ```bash
  aws sts get-caller-identity
  ```
- [ ] Sufficient AWS quotas:
  - [ ] VPCs: 2 (one per region)
  - [ ] EC2 instances: 6 (3 per region)
  - [ ] EBS volumes: 6 (3 per region)
  - [ ] Elastic IPs: 6 (3 per region for NAT Gateways)
  - [ ] Network Load Balancers: 2 (one per region)

### 2. **Required Credentials**

- [ ] **Vault Enterprise License** (REQUIRED)
  - Get from: https://portal.hashicorp.com
  - Format: Long string starting with "02MV4UU..."
  
- [ ] **AWS Credentials** configured
  ```bash
  # Option 1: Environment variables
  export AWS_ACCESS_KEY_ID="your-key"
  export AWS_SECRET_ACCESS_KEY="your-secret"
  
  # Option 2: AWS CLI profile
  export AWS_PROFILE="your-profile"
  ```

### 3. **Configuration File**

- [ ] Copy example configuration:
  ```bash
  cp terraform.tfvars.example terraform.tfvars
  ```

- [ ] Edit `terraform.tfvars` with your values:
  ```bash
  nano terraform.tfvars
  ```

- [ ] **REQUIRED variables to set:**
  - [ ] `vault_license` - Your Vault Enterprise license
  - [ ] `allowed_inbound_cidrs` - CIDR blocks that can access Vault
  - [ ] `primary_region` - AWS region for primary (default: us-east-1)
  - [ ] `dr_region` - AWS region for DR (default: us-east-2)

- [ ] **OPTIONAL but recommended:**
  - [ ] `environment` - Environment name (prod, dev, etc.)
  - [ ] `owner` - Team or person responsible
  - [ ] `vault_instance_type` - Instance size (default: t3.xlarge)
  - [ ] `allowed_ssh_cidrs` - For SSH access (leave empty for SSM only)

### 4. **Network Planning**

- [ ] Verify VPC CIDRs don't conflict with existing networks:
  - Primary: `10.0.0.0/16` (default)
  - DR: `10.1.0.0/16` (default)

- [ ] Confirm allowed inbound CIDRs are correct:
  ```hcl
  allowed_inbound_cidrs = [
    "10.0.0.0/8",      # Your internal network
    "203.0.113.0/24"   # Your office network
  ]
  ```

### 5. **Cost Awareness**

- [ ] Understand estimated monthly costs: **~$802/month**
  - Primary cluster: ~$401/month
  - DR cluster: ~$401/month
  
- [ ] Components:
  - 6x t3.xlarge instances: ~$600/month
  - 6x 100GB EBS volumes: ~$60/month
  - 2x Network Load Balancers: ~$40/month
  - 2x KMS keys: ~$2/month
  - Data transfer: ~$100/month

### 6. **Terraform Setup**

- [ ] Terraform installed (>= 1.5.0):
  ```bash
  terraform version
  ```

- [ ] In project directory:
  ```bash
  cd /path/to/tfe-onprem-vcenter
  ```

### 7. **File Structure Verification**

- [ ] Verify all required files exist:
  ```bash
  ls -la
  # Should see:
  # - main.tf
  # - variables.tf
  # - outputs.tf
  # - versions.tf
  # - terraform.tfvars (your config)
  # - modules/vault-cluster/
  ```

- [ ] Check module files:
  ```bash
  ls -la modules/vault-cluster/
  # Should see:
  # - main.tf
  # - variables.tf
  # - outputs.tf
  # - templates/user-data.sh.tpl
  ```

## 🚀 Deployment Steps

### Step 1: Initialize Terraform

```bash
terraform init
```

**Expected output:**
- Downloads AWS provider
- Initializes modules
- Creates `.terraform` directory
- Shows "Terraform has been successfully initialized!"

### Step 2: Validate Configuration

```bash
terraform validate
```

**Expected output:**
- "Success! The configuration is valid."

### Step 3: Plan Deployment

```bash
terraform plan -out=tfplan
```

**Expected output:**
- Shows ~90 resources to be created
- Review the plan carefully
- Verify regions, instance types, and configurations

**Key resources to verify:**
- [ ] 2 VPCs (one per region)
- [ ] 12 subnets (6 per region: 3 public + 3 private)
- [ ] 6 NAT Gateways (3 per region)
- [ ] 6 EC2 instances (3 per region)
- [ ] 6 EBS volumes (3 per region)
- [ ] 2 Network Load Balancers
- [ ] 2 KMS keys
- [ ] Security groups
- [ ] IAM roles and policies

### Step 4: Apply Configuration

```bash
terraform apply tfplan
```

**Deployment time:** ~15-20 minutes

**What happens:**
1. Creates VPCs and networking (2-3 min)
2. Creates security groups and IAM roles (1-2 min)
3. Creates KMS keys (1 min)
4. Launches EC2 instances (5-10 min)
5. Configures load balancers (2-3 min)
6. Instances run user-data script to install Vault (5-10 min)

### Step 5: Verify Deployment

```bash
# Get outputs
terraform output

# Check connection info
terraform output connection_info
```

**Verify:**
- [ ] All instances are running
- [ ] Load balancers are healthy
- [ ] Security groups are configured
- [ ] KMS keys are created

## 📋 Post-Deployment Steps

### 1. Initialize Primary Vault Cluster

```bash
# Get primary load balancer DNS
PRIMARY_LB=$(terraform output -json | jq -r '.primary_cluster.value.load_balancer.dns_name')

# Set Vault address
export VAULT_ADDR="https://$PRIMARY_LB:8200"
export VAULT_SKIP_VERIFY=1

# Initialize Vault
vault operator init -key-shares=5 -key-threshold=3 | tee primary-init-keys.txt

# IMPORTANT: Save the unseal keys and root token!
```

### 2. Initialize DR Vault Cluster

```bash
# Get DR load balancer DNS
DR_LB=$(terraform output -json | jq -r '.dr_cluster.value.load_balancer.dns_name')

# Set Vault address
export VAULT_ADDR="https://$DR_LB:8200"

# Initialize Vault
vault operator init -key-shares=5 -key-threshold=3 | tee dr-init-keys.txt

# IMPORTANT: Save the unseal keys and root token!
```

### 3. Verify Vault Status

```bash
# Check primary
export VAULT_ADDR="https://$PRIMARY_LB:8200"
vault status

# Check DR
export VAULT_ADDR="https://$DR_LB:8200"
vault status
```

**Expected status:**
- Initialized: true
- Sealed: false (if auto-unseal is working)
- HA Enabled: true

### 4. Enable DR Replication

See `docs/DEPLOYMENT-GUIDE.md` for detailed DR replication setup.

## ⚠️ Important Notes

### Security

1. **Save initialization keys securely!**
   - Store in a password manager
   - Keep offline backup
   - Never commit to git

2. **Network access:**
   - Vault is in private subnets by default
   - Use VPN, bastion host, or VPC peering to access
   - Or use AWS Systems Manager Session Manager

3. **SSH access:**
   - If `allowed_ssh_cidrs` is empty, use SSM:
     ```bash
     aws ssm start-session --target <instance-id>
     ```

### Troubleshooting

**If deployment fails:**

1. Check AWS quotas:
   ```bash
   aws service-quotas list-service-quotas --service-code ec2
   ```

2. Check Terraform logs:
   ```bash
   TF_LOG=DEBUG terraform apply
   ```

3. Verify AWS credentials:
   ```bash
   aws sts get-caller-identity
   ```

4. Check instance logs:
   ```bash
   # Via SSM
   aws ssm start-session --target <instance-id>
   sudo tail -f /var/log/user-data.log
   ```

**Common issues:**

- **Quota exceeded:** Request quota increase in AWS console
- **Invalid license:** Verify license string is correct
- **Network timeout:** Check security groups and NACLs
- **KMS access denied:** Verify IAM role has KMS permissions

## 🧹 Cleanup (When Done Testing)

```bash
# Destroy all resources
terraform destroy

# Confirm by typing 'yes'
```

**Warning:** This permanently deletes all resources including data!

## ✅ Final Checklist Before Apply

- [ ] `terraform.tfvars` configured with valid license
- [ ] AWS credentials configured
- [ ] Network CIDRs reviewed
- [ ] Cost estimate understood (~$802/month)
- [ ] `terraform init` completed successfully
- [ ] `terraform validate` passed
- [ ] `terraform plan` reviewed
- [ ] Ready to run `terraform apply`

---

**You're ready to deploy!** 🚀

Run: `terraform apply`