# ============================================================================
# Vault Cluster Module - Variables
# ============================================================================

# ============================================================================
# General Configuration
# ============================================================================

variable "cluster_name" {
  description = "Name of the Vault cluster"
  type        = string
}

variable "region" {
  description = "AWS region for this cluster"
  type        = string
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "allowed_inbound_cidrs" {
  description = "CIDR blocks allowed to access Vault API"
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = []
}

# ============================================================================
# Vault Configuration
# ============================================================================

variable "vault_version" {
  description = "Vault Enterprise version"
  type        = string
}

variable "vault_license" {
  description = "Vault Enterprise license"
  type        = string
  sensitive   = true
}

variable "vault_node_count" {
  description = "Number of Vault nodes"
  type        = number
}

# ============================================================================
# EC2 Configuration
# ============================================================================

variable "instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for Vault instances (empty for auto-lookup)"
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
}

variable "data_volume_size" {
  description = "Size of data volume in GB"
  type        = number
}

variable "data_volume_type" {
  description = "EBS volume type"
  type        = string
}

variable "data_volume_iops" {
  description = "IOPS for data volume"
  type        = number
}

variable "data_volume_throughput" {
  description = "Throughput for data volume in MB/s"
  type        = number
}

# ============================================================================
# Load Balancer Configuration
# ============================================================================

variable "lb_internal" {
  description = "Whether load balancer is internal"
  type        = bool
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
}

# ============================================================================
# Auto-Unseal Configuration
# ============================================================================

variable "enable_auto_unseal" {
  description = "Enable AWS KMS auto-unseal"
  type        = bool
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
}

variable "enable_kms_key_rotation" {
  description = "Enable KMS key rotation"
  type        = bool
}

# ============================================================================
# Monitoring & Logging
# ============================================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs"
  type        = bool
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
}

variable "enable_audit_logging" {
  description = "Enable Vault audit logging"
  type        = bool
}

# ============================================================================
# Backup Configuration
# ============================================================================

variable "enable_ebs_snapshots" {
  description = "Enable EBS snapshots"
  type        = bool
}

variable "snapshot_retention_days" {
  description = "Snapshot retention in days"
  type        = number
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "enable_ebs_encryption" {
  description = "Enable EBS encryption"
  type        = bool
}

variable "enable_imdsv2" {
  description = "Require IMDSv2"
  type        = bool
}

# ============================================================================
# Feature Flags
# ============================================================================

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection"
  type        = bool
}

variable "enable_deletion_protection_lb" {
  description = "Enable LB deletion protection"
  type        = bool
}

# ============================================================================
# DR Configuration
# ============================================================================

variable "is_dr_cluster" {
  description = "Whether this is a DR cluster"
  type        = bool
  default     = false
}

variable "dr_peer_vpc_id" {
  description = "VPC ID of DR peer cluster"
  type        = string
  default     = ""
}

variable "dr_peer_cidr" {
  description = "CIDR of DR peer cluster"
  type        = string
  default     = ""
}

variable "enable_dr_replication" {
  description = "Enable DR replication"
  type        = bool
}

# ============================================================================
# Auto-Initialization Configuration
# ============================================================================

variable "enable_auto_init" {
  description = "Automatically initialize Vault on Node 1 and store credentials in Secrets Manager"
  type        = bool
  default     = true
}

# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
