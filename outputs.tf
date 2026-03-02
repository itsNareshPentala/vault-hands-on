# ============================================================================
# Primary Cluster Outputs
# ============================================================================

output "primary_cluster" {
  description = "Primary Vault cluster information"
  value = {
    cluster_name = var.vault_cluster_name_primary
    region       = var.primary_region
    vpc_id       = module.primary_cluster.vpc_id

    load_balancer = {
      dns_name = module.primary_cluster.lb_dns_name
      arn      = module.primary_cluster.lb_arn
      url      = "https://${module.primary_cluster.lb_dns_name}:8200"
      ui_url   = "https://${module.primary_cluster.lb_dns_name}:8200/ui"
    }

    nodes = {
      instance_ids       = module.primary_cluster.instance_ids
      private_ips        = module.primary_cluster.private_ips
      availability_zones = module.primary_cluster.availability_zones
    }

    kms = {
      key_id  = module.primary_cluster.kms_key_id
      key_arn = module.primary_cluster.kms_key_arn
    }

    security_groups = {
      vault_sg_id = module.primary_cluster.vault_security_group_id
      lb_sg_id    = module.primary_cluster.lb_security_group_id
    }
  }
}

# ============================================================================
# DR Cluster Outputs
# ============================================================================

output "dr_cluster" {
  description = "DR Vault cluster information"
  value = {
    cluster_name = var.vault_cluster_name_dr
    region       = var.dr_region
    vpc_id       = module.dr_cluster.vpc_id

    load_balancer = {
      dns_name = module.dr_cluster.lb_dns_name
      arn      = module.dr_cluster.lb_arn
      url      = "https://${module.dr_cluster.lb_dns_name}:8200"
      ui_url   = "https://${module.dr_cluster.lb_dns_name}:8200/ui"
    }

    nodes = {
      instance_ids       = module.dr_cluster.instance_ids
      private_ips        = module.dr_cluster.private_ips
      availability_zones = module.dr_cluster.availability_zones
    }

    kms = {
      key_id  = module.dr_cluster.kms_key_id
      key_arn = module.dr_cluster.kms_key_arn
    }

    security_groups = {
      vault_sg_id = module.dr_cluster.vault_security_group_id
      lb_sg_id    = module.dr_cluster.lb_security_group_id
    }
  }
}

# ============================================================================
# SSH Key Information
# ============================================================================

output "ssh_key_info" {
  description = "SSH key information for accessing Vault instances"
  value = {
    primary_key_name = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.vault_primary[0].key_name
    dr_key_name      = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.vault_dr[0].key_name
    private_key_path = var.ssh_key_name == "" ? "${path.module}/vault-ssh-key.pem" : "Use your existing key"
  }
}

# ============================================================================
# VPC Peering Information
# ============================================================================

output "vpc_peering" {
  description = "VPC peering connection information"
  value = var.enable_vpc_peering ? {
    peering_connection_id = aws_vpc_peering_connection.primary_to_dr[0].id
    status                = aws_vpc_peering_connection.primary_to_dr[0].accept_status
    primary_vpc_id        = module.primary_cluster.vpc_id
    dr_vpc_id             = module.dr_cluster.vpc_id
  } : null
}

# ============================================================================
# Connection Information
# ============================================================================

output "connection_info" {
  description = "Quick reference for connecting to Vault clusters"
  value       = <<-EOT
  
  ╔════════════════════════════════════════════════════════════════════════════╗
  ║                    Vault Enterprise DR Deployment                          ║
  ╚════════════════════════════════════════════════════════════════════════════╝
  
  PRIMARY CLUSTER (${var.primary_region})
  ─────────────────────────────────────────────────────────────────────────────
  Vault API:     https://${module.primary_cluster.lb_dns_name}:8200
  Vault UI:      https://${module.primary_cluster.lb_dns_name}:8200/ui
  
  Nodes:
  %{for idx, ip in module.primary_cluster.private_ips~}
  - Node ${idx + 1}: ${ip} (${module.primary_cluster.availability_zones[idx]})
  %{endfor~}
  
  DR CLUSTER (${var.dr_region})
  ─────────────────────────────────────────────────────────────────────────────
  Vault API:     https://${module.dr_cluster.lb_dns_name}:8200
  Vault UI:      https://${module.dr_cluster.lb_dns_name}:8200/ui
  
  Nodes:
  %{for idx, ip in module.dr_cluster.private_ips~}
  - Node ${idx + 1}: ${ip} (${module.dr_cluster.availability_zones[idx]})
  %{endfor~}
  
  NEXT STEPS
  ─────────────────────────────────────────────────────────────────────────────
  %{if var.enable_auto_init~}
  Auto-initialization is ENABLED. Node 1 will initialize each cluster
  automatically and store root token + recovery keys in S3.
  
  1. Retrieve Primary credentials:
     aws s3 cp ${module.primary_cluster.vault_init_s3_uri != null ? module.primary_cluster.vault_init_s3_uri : "N/A"} - --region ${var.primary_region} | jq .
  
  2. Retrieve DR credentials:
     aws s3 cp ${module.dr_cluster.vault_init_s3_uri != null ? module.dr_cluster.vault_init_s3_uri : "N/A"} - --region ${var.dr_region} | jq .
  
  3. Enable DR Replication (manual):
     See docs/DEPLOYMENT-GUIDE.md for detailed instructions
  %{else~}
  Auto-initialization is DISABLED. Manual steps required:
  
  1. Initialize Primary Cluster:
     export VAULT_ADDR="https://${module.primary_cluster.lb_dns_name}:8200"
     export VAULT_SKIP_VERIFY=1
     vault operator init -recovery-shares=5 -recovery-threshold=3
  
  2. Initialize DR Cluster:
     export VAULT_ADDR="https://${module.dr_cluster.lb_dns_name}:8200"
     vault operator init -recovery-shares=5 -recovery-threshold=3
  
  3. Enable DR Replication:
     See docs/DEPLOYMENT-GUIDE.md for detailed instructions
  %{endif~}
  
  SSH ACCESS
  ─────────────────────────────────────────────────────────────────────────────
  Primary Node 1: ssh -i ${var.ssh_key_name == "" ? "vault-ssh-key.pem" : "your-key.pem"} ubuntu@${module.primary_cluster.private_ips[0]}
  DR Node 1:      ssh -i ${var.ssh_key_name == "" ? "vault-ssh-key.pem" : "your-key.pem"} ubuntu@${module.dr_cluster.private_ips[0]}
  
  Note: Nodes are in private subnets. Use bastion host or VPN for access.
  
  MONITORING
  ─────────────────────────────────────────────────────────────────────────────
  CloudWatch Logs: /aws/vault/${var.vault_cluster_name_primary}
                   /aws/vault/${var.vault_cluster_name_dr}
  
  ╚════════════════════════════════════════════════════════════════════════════╝
  EOT
}

# ============================================================================
# Terraform Configuration Summary
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    vault_version     = var.vault_version
    instance_type     = var.vault_instance_type
    nodes_per_cluster = var.vault_node_count
    total_nodes       = var.vault_node_count * 2
    auto_unseal       = var.enable_auto_unseal ? "AWS KMS" : "Shamir"
    vpc_peering       = var.enable_vpc_peering
    dr_replication    = var.enable_dr_replication

    estimated_monthly_cost = {
      primary_cluster = "~$401 USD"
      dr_cluster      = "~$401 USD"
      total           = "~$802 USD"
      note            = "Estimate includes EC2, EBS, NLB, KMS, and data transfer"
    }
  }
}

# ============================================================================
# Sensitive Outputs (marked as sensitive)
# ============================================================================

output "kms_key_ids" {
  description = "KMS key IDs for auto-unseal (sensitive)"
  value = {
    primary = module.primary_cluster.kms_key_id
    dr      = module.dr_cluster.kms_key_id
  }
  sensitive = true
}

output "private_key_pem" {
  description = "Private SSH key (if generated)"
  value       = var.ssh_key_name == "" ? tls_private_key.vault_ssh[0].private_key_pem : "Using existing key"
  sensitive   = true
}

# ============================================================================
# Vault Init Credentials (S3 URIs)
# ============================================================================

output "vault_init_secrets" {
  description = "S3 URIs containing Vault init credentials (root token + recovery keys)"
  value = var.enable_auto_init ? {
    primary_init_s3_uri  = module.primary_cluster.vault_init_s3_uri
    dr_init_s3_uri       = module.dr_cluster.vault_init_s3_uri
    retrieve_primary_cmd = "aws s3 cp ${module.primary_cluster.vault_init_s3_uri} - --region ${var.primary_region} | jq ."
    retrieve_dr_cmd      = "aws s3 cp ${module.dr_cluster.vault_init_s3_uri} - --region ${var.dr_region} | jq ."
  } : null
}

