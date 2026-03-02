# Vault Enterprise DR on AWS - Main Configuration
# This configuration deploys a production-ready Vault Enterprise setup with
# DR replication across two AWS regions following HashiCorp Validated Designs

# ============================================================================
# SSH Key Pair Generation (if not provided)
# ============================================================================

resource "tls_private_key" "vault_ssh" {
  count     = var.ssh_key_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vault_primary" {
  count      = var.ssh_key_name == "" ? 1 : 0
  key_name   = "${var.project_name}-primary-key"
  public_key = tls_private_key.vault_ssh[0].public_key_openssh

  tags = {
    Name = "${var.project_name}-primary-key"
  }
}

resource "aws_key_pair" "vault_dr" {
  count      = var.ssh_key_name == "" ? 1 : 0
  provider   = aws.dr
  key_name   = "${var.project_name}-dr-key"
  public_key = tls_private_key.vault_ssh[0].public_key_openssh

  tags = {
    Name = "${var.project_name}-dr-key"
  }
}

resource "local_file" "private_key" {
  count           = var.ssh_key_name == "" ? 1 : 0
  content         = tls_private_key.vault_ssh[0].private_key_pem
  filename        = "${path.module}/vault-ssh-key.pem"
  file_permission = "0600"
}

# ============================================================================
# Primary Region Deployment
# ============================================================================

module "primary_cluster" {
  source = "./modules/vault-cluster"

  # General Configuration
  cluster_name = var.vault_cluster_name_primary
  region       = var.primary_region

  # Network Configuration
  vpc_cidr              = var.primary_vpc_cidr
  allowed_inbound_cidrs = var.allowed_inbound_cidrs
  allowed_ssh_cidrs     = var.allowed_ssh_cidrs

  # Vault Configuration
  vault_version    = var.vault_version
  vault_license    = var.vault_license
  vault_node_count = var.vault_node_count

  # EC2 Configuration
  instance_type          = var.vault_instance_type
  ami_id                 = var.ami_id_primary
  ssh_key_name           = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.vault_primary[0].key_name
  root_volume_size       = var.vault_root_volume_size
  data_volume_size       = var.vault_data_volume_size
  data_volume_type       = var.vault_data_volume_type
  data_volume_iops       = var.vault_data_volume_iops
  data_volume_throughput = var.vault_data_volume_throughput

  # Load Balancer Configuration
  lb_internal                      = var.lb_internal
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Auto-Unseal Configuration
  enable_auto_unseal      = var.enable_auto_unseal
  kms_key_deletion_window = var.kms_key_deletion_window
  enable_kms_key_rotation = var.enable_kms_key_rotation

  # Monitoring & Logging
  enable_cloudwatch_logs        = var.enable_cloudwatch_logs
  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  enable_detailed_monitoring    = var.enable_detailed_monitoring
  enable_audit_logging          = var.enable_audit_logging

  # Backup Configuration
  enable_ebs_snapshots    = var.enable_ebs_snapshots
  snapshot_retention_days = var.snapshot_retention_days

  # Security Configuration
  enable_ebs_encryption = var.enable_ebs_encryption
  enable_imdsv2         = var.enable_imdsv2

  # Feature Flags
  enable_termination_protection = var.enable_termination_protection
  enable_deletion_protection_lb = var.enable_deletion_protection_lb

  # Auto-Initialization
  enable_auto_init = var.enable_auto_init

  # DR Configuration
  is_dr_cluster         = false
  dr_peer_vpc_id        = var.enable_vpc_peering ? module.dr_cluster.vpc_id : ""
  dr_peer_cidr          = var.enable_vpc_peering ? var.dr_vpc_cidr : ""
  enable_dr_replication = var.enable_dr_replication

  # Tags
  additional_tags = var.additional_tags
}

# ============================================================================
# DR Region Deployment
# ============================================================================

module "dr_cluster" {
  source = "./modules/vault-cluster"
  providers = {
    aws = aws.dr
  }

  # General Configuration
  cluster_name = var.vault_cluster_name_dr
  region       = var.dr_region

  # Network Configuration
  vpc_cidr              = var.dr_vpc_cidr
  allowed_inbound_cidrs = var.allowed_inbound_cidrs
  allowed_ssh_cidrs     = var.allowed_ssh_cidrs

  # Vault Configuration
  vault_version    = var.vault_version
  vault_license    = var.vault_license
  vault_node_count = var.vault_node_count

  # EC2 Configuration
  instance_type          = var.vault_instance_type
  ami_id                 = var.ami_id_dr
  ssh_key_name           = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.vault_dr[0].key_name
  root_volume_size       = var.vault_root_volume_size
  data_volume_size       = var.vault_data_volume_size
  data_volume_type       = var.vault_data_volume_type
  data_volume_iops       = var.vault_data_volume_iops
  data_volume_throughput = var.vault_data_volume_throughput

  # Load Balancer Configuration
  lb_internal                      = var.lb_internal
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Auto-Unseal Configuration
  enable_auto_unseal      = var.enable_auto_unseal
  kms_key_deletion_window = var.kms_key_deletion_window
  enable_kms_key_rotation = var.enable_kms_key_rotation

  # Monitoring & Logging
  enable_cloudwatch_logs        = var.enable_cloudwatch_logs
  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  enable_detailed_monitoring    = var.enable_detailed_monitoring
  enable_audit_logging          = var.enable_audit_logging

  # Backup Configuration
  enable_ebs_snapshots    = var.enable_ebs_snapshots
  snapshot_retention_days = var.snapshot_retention_days

  # Security Configuration
  enable_ebs_encryption = var.enable_ebs_encryption
  enable_imdsv2         = var.enable_imdsv2

  # Feature Flags
  enable_termination_protection = var.enable_termination_protection
  enable_deletion_protection_lb = var.enable_deletion_protection_lb

  # Auto-Initialization
  enable_auto_init = var.enable_auto_init

  # DR Configuration
  is_dr_cluster         = true
  dr_peer_vpc_id        = var.enable_vpc_peering ? module.primary_cluster.vpc_id : ""
  dr_peer_cidr          = var.enable_vpc_peering ? var.primary_vpc_cidr : ""
  enable_dr_replication = var.enable_dr_replication

  # Tags
  additional_tags = var.additional_tags
}

# ============================================================================
# VPC Peering (for DR Replication)
# ============================================================================

resource "aws_vpc_peering_connection" "primary_to_dr" {
  count       = var.enable_vpc_peering ? 1 : 0
  vpc_id      = module.primary_cluster.vpc_id
  peer_vpc_id = module.dr_cluster.vpc_id
  peer_region = var.dr_region
  auto_accept = false

  tags = {
    Name = "${var.project_name}-primary-to-dr"
    Side = "Requester"
  }
}

resource "aws_vpc_peering_connection_accepter" "dr_accept" {
  count                     = var.enable_vpc_peering ? 1 : 0
  provider                  = aws.dr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_dr[0].id
  auto_accept               = true

  tags = {
    Name = "${var.project_name}-dr-accept"
    Side = "Accepter"
  }
}

# ============================================================================
# Route Table Updates for VPC Peering
# ============================================================================
# Add peering routes to ALL private route tables (one per AZ) so that nodes
# in every AZ can reach the peer VPC for DR replication traffic (port 8201).

resource "aws_route" "primary_to_dr" {
  count                     = var.enable_vpc_peering ? length(module.primary_cluster.private_route_table_ids) : 0
  route_table_id            = module.primary_cluster.private_route_table_ids[count.index]
  destination_cidr_block    = var.dr_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_dr[0].id
}

resource "aws_route" "dr_to_primary" {
  count                     = var.enable_vpc_peering ? length(module.dr_cluster.private_route_table_ids) : 0
  provider                  = aws.dr
  route_table_id            = module.dr_cluster.private_route_table_ids[count.index]
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_dr[0].id
}
