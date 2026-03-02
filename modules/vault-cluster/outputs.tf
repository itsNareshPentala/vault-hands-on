# ============================================================================
# Vault Cluster Module - Outputs
# ============================================================================

# ============================================================================
# VPC Outputs
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "Private route table ID (first one, used for VPC peering)"
  value       = aws_route_table.private[0].id
}

output "private_route_table_ids" {
  description = "All private route table IDs (one per AZ)"
  value       = aws_route_table.private[*].id
}

# ============================================================================
# Security Group Outputs
# ============================================================================

output "vault_security_group_id" {
  description = "Vault security group ID"
  value       = aws_security_group.vault.id
}

output "lb_security_group_id" {
  description = "Load balancer security group ID"
  value       = aws_security_group.lb.id
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "vault_iam_role_arn" {
  description = "Vault IAM role ARN"
  value       = aws_iam_role.vault.arn
}

output "vault_iam_role_name" {
  description = "Vault IAM role name"
  value       = aws_iam_role.vault.name
}

output "vault_instance_profile_arn" {
  description = "Vault instance profile ARN"
  value       = aws_iam_instance_profile.vault.arn
}

# ============================================================================
# KMS Outputs
# ============================================================================

output "kms_key_id" {
  description = "KMS key ID for auto-unseal"
  value       = var.enable_auto_unseal ? aws_kms_key.vault[0].id : null
}

output "kms_key_arn" {
  description = "KMS key ARN for auto-unseal"
  value       = var.enable_auto_unseal ? aws_kms_key.vault[0].arn : null
}

# ============================================================================
# EC2 Instance Outputs
# ============================================================================

output "instance_ids" {
  description = "Vault instance IDs"
  value       = aws_instance.vault[*].id
}

output "private_ips" {
  description = "Private IP addresses of Vault instances"
  value       = aws_instance.vault[*].private_ip
}

output "availability_zones" {
  description = "Availability zones of Vault instances"
  value       = aws_instance.vault[*].availability_zone
}

output "data_volume_ids" {
  description = "EBS data volume IDs (inline on instances)"
  value       = [for inst in aws_instance.vault : inst.ebs_block_device.*.volume_id]
}

# ============================================================================
# Load Balancer Outputs
# ============================================================================

output "lb_arn" {
  description = "Load balancer ARN"
  value       = aws_lb.vault.arn
}

output "lb_dns_name" {
  description = "Load balancer DNS name"
  value       = aws_lb.vault.dns_name
}

output "lb_zone_id" {
  description = "Load balancer zone ID"
  value       = aws_lb.vault.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.vault_api.arn
}

# ============================================================================
# TLS Certificate Outputs
# ============================================================================

output "tls_s3_uri" {
  description = "S3 URI of TLS certificates JSON"
  value       = "s3://${aws_s3_bucket.vault_scripts.id}/${aws_s3_object.vault_tls.key}"
}

output "ca_cert_pem" {
  description = "CA certificate PEM"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "vault_init_s3_uri" {
  description = "S3 URI where Vault init credentials (root token + recovery keys) will be stored"
  value       = var.enable_auto_init ? "s3://${aws_s3_bucket.vault_scripts.id}/init/vault-init.json" : null
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for Vault logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.vault[0].name : null
}

output "cloudwatch_audit_log_group_name" {
  description = "CloudWatch log group name for Vault audit logs"
  value       = var.enable_audit_logging ? aws_cloudwatch_log_group.vault_audit[0].name : null
}

# ============================================================================
# Cluster Information
# ============================================================================

output "cluster_info" {
  description = "Comprehensive cluster information"
  value = {
    cluster_name        = var.cluster_name
    region              = var.region
    vault_version       = var.vault_version
    node_count          = var.vault_node_count
    instance_type       = var.instance_type
    auto_unseal_enabled = var.enable_auto_unseal
    is_dr_cluster       = var.is_dr_cluster
  }
}
