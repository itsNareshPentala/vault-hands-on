# ============================================================================
# DEMO/POC Configuration - Cost Optimized (~$400-450/month)
# ============================================================================
# This configuration is optimized for demonstrations, testing, and POCs
# NOT recommended for production use - no high availability
# ============================================================================

# ----------------------------------------------------------------------------
# General Configuration
# ----------------------------------------------------------------------------
environment  = "demo"
owner        = "your-name"
project_name = "vault-dr-demo"

# ----------------------------------------------------------------------------
# Region Configuration - Same Region for Cost Savings
# ----------------------------------------------------------------------------
primary_region = "us-east-1"
dr_region      = "us-east-2" # Same region to save on data transfer costs

# ----------------------------------------------------------------------------
# Network Configuration
# ----------------------------------------------------------------------------
primary_vpc_cidr = "10.0.0.0/16"
dr_vpc_cidr      = "10.1.0.0/16"

# Allow access from your IP only (replace with your actual IP)
allowed_inbound_cidrs = ["0.0.0.0/0"] # CHANGE THIS to your IP for security
allowed_ssh_cidrs     = ["0.0.0.0/0"] # CHANGE THIS to your IP for security

# Enable VPC peering for DR replication
enable_vpc_peering = true

# ----------------------------------------------------------------------------
# Vault Configuration
# ----------------------------------------------------------------------------
vault_version = "1.21.1+ent"
vault_license = "XXXXXXXXXXXXXXXXXXXXXXX" # Required

# Cluster names
vault_cluster_name_primary = "vault-primary"
vault_cluster_name_dr      = "vault-dr"

# DEMO: Single node per cluster (no HA, but functional for testing)
vault_node_count = 1 # Reduced from 3 for demo

# ----------------------------------------------------------------------------
# EC2 Configuration - Smaller Instances for Demo
# ----------------------------------------------------------------------------
vault_instance_type = "t3.medium" # 2 vCPU, 4GB RAM (good for demo)

# Smaller EBS volumes
vault_root_volume_size       = 30 # Reduced from 50GB
vault_data_volume_size       = 30 # Reduced from 100GB
vault_data_volume_type       = "gp3"
vault_data_volume_iops       = 3000
vault_data_volume_throughput = 125

# Use latest Ubuntu AMI (auto-lookup)
ami_id_primary = ""
ami_id_dr      = ""

# SSH key (will be auto-generated)
ssh_key_name = ""

# ----------------------------------------------------------------------------
# Load Balancer Configuration
# ----------------------------------------------------------------------------
lb_internal                      = false # External for easy demo access
enable_cross_zone_load_balancing = true

# ----------------------------------------------------------------------------
# KMS Configuration
# ----------------------------------------------------------------------------
enable_auto_unseal      = true
kms_key_deletion_window = 7     # Minimum allowed
enable_kms_key_rotation = false # Disable for demo

# ----------------------------------------------------------------------------
# Monitoring Configuration - Disabled for Cost Savings
# ----------------------------------------------------------------------------
enable_cloudwatch_logs        = false # Save on CloudWatch costs
cloudwatch_log_retention_days = 1     # Minimum retention
enable_detailed_monitoring    = false
enable_audit_logging          = false

# ----------------------------------------------------------------------------
# Backup Configuration - Disabled for Demo
# ----------------------------------------------------------------------------
enable_ebs_snapshots    = false # No automated backups
snapshot_retention_days = 1

# ----------------------------------------------------------------------------
# Security Configuration
# ----------------------------------------------------------------------------
enable_ebs_encryption = true
enable_imdsv2         = true

# ----------------------------------------------------------------------------
# Protection Configuration
# ----------------------------------------------------------------------------
enable_termination_protection = false # Disabled for demo (easy teardown)
enable_deletion_protection_lb = false # Disabled for demo (easy teardown)

# ----------------------------------------------------------------------------
# Auto-Initialization Configuration
# ----------------------------------------------------------------------------
enable_auto_init = true # Auto-init Vault and store creds in Secrets Manager

# ----------------------------------------------------------------------------
# DR Replication Configuration
# ----------------------------------------------------------------------------
enable_dr_replication = true

# ----------------------------------------------------------------------------
# Additional Tags
# ----------------------------------------------------------------------------
additional_tags = {
  Environment  = "demo"
  Purpose      = "poc-testing"
  CostCenter   = "demo"
  AutoShutdown = "true" # Tag for auto-shutdown scripts
  ManagedBy    = "terraform"
}
