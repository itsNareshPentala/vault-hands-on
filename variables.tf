# ============================================================================
# General Configuration
# ============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "platform-team"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "vault-integration-lab"
}

# ============================================================================
# Region Configuration
# ============================================================================

variable "primary_region" {
  description = "AWS region for primary Vault cluster"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS region for DR Vault cluster"
  type        = string
  default     = "us-east-2"
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "primary_vpc_cidr" {
  description = "CIDR block for primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "enable_vpc_peering" {
  description = "Enable VPC peering between primary and DR regions for replication"
  type        = bool
  default     = true
}

variable "allowed_inbound_cidrs" {
  description = "List of CIDR blocks allowed to access Vault API"
  type        = list(string)
  default     = ["10.0.0.0/8"] # Adjust based on your network
}

# ============================================================================
# Vault Configuration
# ============================================================================

variable "vault_version" {
  description = "Vault Enterprise version to install"
  type        = string
  default     = "1.21.1+ent"
}

variable "vault_license" {
  description = "Vault Enterprise license key"
  type        = string
  sensitive   = true
}

variable "vault_cluster_name_primary" {
  description = "Name for primary Vault cluster"
  type        = string
  default     = "vault-primary"
}

variable "vault_cluster_name_dr" {
  description = "Name for DR Vault cluster"
  type        = string
  default     = "vault-dr"
}

variable "vault_node_count" {
  description = "Number of Vault nodes per cluster (1 for demo, 3+ for production with HA)"
  type        = number
  default     = 3

  validation {
    condition     = var.vault_node_count >= 1 && var.vault_node_count <= 7
    error_message = "Vault node count must be between 1 and 7. Use 1 for demo/testing, 3+ for production HA."
  }
}

# ============================================================================
# EC2 Configuration
# ============================================================================

variable "vault_instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
  default     = "t3.xlarge" # 4 vCPU, 16 GB RAM
}

variable "vault_root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 50
}

variable "vault_data_volume_size" {
  description = "Size of data volume for Raft storage in GB"
  type        = number
  default     = 100
}

variable "vault_data_volume_type" {
  description = "EBS volume type for Raft storage"
  type        = string
  default     = "gp3"
}

variable "vault_data_volume_iops" {
  description = "IOPS for data volume (gp3 only)"
  type        = number
  default     = 3000
}

variable "vault_data_volume_throughput" {
  description = "Throughput for data volume in MB/s (gp3 only)"
  type        = number
  default     = 125
}

variable "ami_id_primary" {
  description = "AMI ID for primary region (Ubuntu 22.04 LTS). Leave empty for auto-lookup"
  type        = string
  default     = ""
}

variable "ami_id_dr" {
  description = "AMI ID for DR region (Ubuntu 22.04 LTS). Leave empty for auto-lookup"
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "Name of existing EC2 key pair for SSH access"
  type        = string
  default     = ""
}

# ============================================================================
# Load Balancer Configuration
# ============================================================================


variable "lb_internal" {
  description = "Whether load balancer should be internal"
  type        = bool
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
  default     = true
}

# ============================================================================
# Auto-Unseal Configuration (AWS KMS)
# ============================================================================

variable "enable_auto_unseal" {
  description = "Enable AWS KMS auto-unseal"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

variable "enable_kms_key_rotation" {
  description = "Enable automatic KMS key rotation"
  type        = bool
  default     = true
}

# ============================================================================
# Monitoring & Logging
# ============================================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for Vault"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 30
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable Vault audit logging to CloudWatch"
  type        = bool
  default     = true
}

# ============================================================================
# Backup Configuration
# ============================================================================

variable "enable_ebs_snapshots" {
  description = "Enable automated EBS snapshots"
  type        = bool
  default     = true
}

variable "snapshot_retention_days" {
  description = "Number of days to retain EBS snapshots"
  type        = number
  default     = 7
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "enable_ebs_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}

variable "enable_imdsv2" {
  description = "Require IMDSv2 for EC2 metadata service"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = [] # Empty = no SSH access
}

# ============================================================================
# DR Replication Configuration
# ============================================================================

variable "enable_dr_replication" {
  description = "Enable DR replication between clusters"
  type        = bool
  default     = true
}


# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Feature Flags
# ============================================================================

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection"
  type        = bool
  default     = true
}

variable "enable_deletion_protection_lb" {
  description = "Enable deletion protection for load balancers"
  type        = bool
  default     = false
}


# ============================================================================
# Auto-Initialization Configuration
# ============================================================================

variable "enable_auto_init" {
  description = "Automatically initialize Vault on Node 1 and store root token + recovery keys in AWS Secrets Manager"
  type        = bool
  default     = true
}

