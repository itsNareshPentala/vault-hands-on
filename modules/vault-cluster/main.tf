# ============================================================================
# Vault Cluster Module - Main Configuration
# ============================================================================
# This module creates a complete Vault cluster with:
# - VPC and networking
# - Security groups
# - IAM roles
# - KMS keys for auto-unseal
# - EC2 instances for Vault nodes
# - Network Load Balancer
# - CloudWatch logging and monitoring
# ============================================================================

# ============================================================================
# Data Sources
# ============================================================================

# Get available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================================
# VPC and Networking
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vpc"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-igw"
    }
  )
}

# Public Subnets (for NLB)
resource "aws_subnet" "public" {
  count                   = min(var.vault_node_count, length(data.aws_availability_zones.available.names))
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-public-${data.aws_availability_zones.available.names[count.index]}"
      Tier = "public"
    }
  )
}

# Private Subnets (for Vault nodes)
resource "aws_subnet" "private" {
  count             = min(var.vault_node_count, length(data.aws_availability_zones.available.names))
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-private-${data.aws_availability_zones.available.names[count.index]}"
      Tier = "private"
    }
  )
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = min(var.vault_node_count, length(data.aws_availability_zones.available.names))
  domain = "vpc"

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count         = min(var.vault_node_count, length(data.aws_availability_zones.available.names))
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-nat-${data.aws_availability_zones.available.names[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-public-rt"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Route (separate resource for better dependency management)
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id

  depends_on = [aws_route_table.public]
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (one per AZ for HA)
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-private-rt-${data.aws_availability_zones.available.names[count.index]}"
    }
  )
}

# Private Routes to NAT Gateways (separate resource for explicit dependency)
resource "aws_route" "private_nat_gateway" {
  count                  = length(aws_subnet.private)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id

  depends_on = [
    aws_nat_gateway.main,
    aws_route_table.private
  ]
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id

  depends_on = [aws_route.private_nat_gateway]
}

# VPC Flow Logs (for security monitoring)
resource "aws_flow_log" "main" {
  count                = var.enable_cloudwatch_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  log_destination_type = "cloud-watch-logs"

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-flow-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/vpc/${var.cluster_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = var.additional_tags

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${var.cluster_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = var.additional_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${var.cluster_name}-flow-logs-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# Security Groups
# ============================================================================

# Vault nodes security group
resource "aws_security_group" "vault" {
  name_prefix = "${var.cluster_name}-vault-"
  description = "Security group for Vault nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Vault API/UI access from NLB
# NLB does NOT use security groups - traffic arrives with client source IP
# Allow from VPC CIDR (covers NLB health checks from public subnets)
resource "aws_security_group_rule" "vault_api_from_lb" {
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.vault.id
  description       = "Vault API/UI from NLB (NLB passes client IP, allow VPC CIDR)"
}

# Allow from internet (for internet-facing NLB - client traffic passes through)
resource "aws_security_group_rule" "vault_api_from_internet" {
  count             = var.lb_internal ? 0 : 1
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = var.allowed_inbound_cidrs
  security_group_id = aws_security_group.vault.id
  description       = "Vault API/UI from internet via NLB (NLB passes client source IP)"
}

# Vault cluster communication (Raft)
resource "aws_security_group_rule" "vault_cluster" {
  type              = "ingress"
  from_port         = 8201
  to_port           = 8201
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.vault.id
  description       = "Vault cluster communication (Raft)"
}

# DR replication from peer cluster
resource "aws_security_group_rule" "vault_dr_replication" {
  count             = var.enable_dr_replication && var.dr_peer_cidr != "" ? 1 : 0
  type              = "ingress"
  from_port         = 8201
  to_port           = 8201
  protocol          = "tcp"
  cidr_blocks       = [var.dr_peer_cidr]
  security_group_id = aws_security_group.vault.id
  description       = "DR replication from peer cluster"
}

# SSH access (if allowed)
resource "aws_security_group_rule" "vault_ssh" {
  count             = length(var.allowed_ssh_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ssh_cidrs
  security_group_id = aws_security_group.vault.id
  description       = "SSH access"
}

# Outbound - allow all
resource "aws_security_group_rule" "vault_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.vault.id
  description       = "Allow all outbound traffic"
}

# Load balancer security group
resource "aws_security_group" "lb" {
  name_prefix = "${var.cluster_name}-lb-"
  description = "Security group for Vault load balancer"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-lb-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# LB inbound from allowed CIDRs
resource "aws_security_group_rule" "lb_inbound" {
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = var.allowed_inbound_cidrs
  security_group_id = aws_security_group.lb.id
  description       = "Vault API access from allowed networks"
}

# LB outbound to Vault nodes (includes health checks)
resource "aws_security_group_rule" "lb_to_vault" {
  type                     = "egress"
  from_port                = 8200
  to_port                  = 8200
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
  security_group_id        = aws_security_group.lb.id
  description              = "Load balancer to Vault nodes (API and health checks)"
}


# ============================================================================
# IAM Roles and Policies
# ============================================================================

# IAM role for Vault instances
resource "aws_iam_role" "vault" {
  name_prefix = "${var.cluster_name}-vault-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-role"
    }
  )
}

# IAM instance profile
resource "aws_iam_instance_profile" "vault" {
  name_prefix = "${var.cluster_name}-vault-"
  role        = aws_iam_role.vault.name

  tags = var.additional_tags
}

# KMS policy for auto-unseal
resource "aws_iam_role_policy" "vault_kms" {
  count = var.enable_auto_unseal ? 1 : 0
  name  = "${var.cluster_name}-kms-policy"
  role  = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.vault[0].arn
      }
    ]
  })
}

# EC2 policy for auto-discovery
resource "aws_iam_role_policy" "vault_ec2" {
  name = "${var.cluster_name}-ec2-policy"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs policy
resource "aws_iam_role_policy" "vault_cloudwatch" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${var.cluster_name}-cloudwatch-policy"
  role  = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/vault/${var.cluster_name}*"
      }
    ]
  })
}

# SSM policy for Session Manager access
resource "aws_iam_role_policy_attachment" "vault_ssm" {
  role       = aws_iam_role.vault.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ============================================================================
# KMS Key for Auto-Unseal
# ============================================================================

resource "aws_kms_key" "vault" {
  count                   = var.enable_auto_unseal ? 1 : 0
  description             = "KMS key for Vault auto-unseal - ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = var.enable_kms_key_rotation

  tags = merge(
    var.additional_tags,
    {
      Name    = "${var.cluster_name}-vault-unseal-key"
      Purpose = "vault-auto-unseal"
    }
  )
}

# Random suffix to ensure KMS alias names are unique across apply/destroy cycles.
# This prevents AlreadyExistsException when an alias was left orphaned in AWS
# (i.e. exists in AWS but not in Terraform state from a previous partial destroy).
resource "random_id" "kms_alias" {
  count       = var.enable_auto_unseal ? 1 : 0
  byte_length = 4
  keepers = {
    # Tie the suffix to the KMS key so it regenerates only when the key changes
    kms_key_id = aws_kms_key.vault[0].key_id
  }
}

resource "aws_kms_alias" "vault" {
  count         = var.enable_auto_unseal ? 1 : 0
  name          = "alias/${var.cluster_name}-vault-unseal-${random_id.kms_alias[0].hex}"
  target_key_id = aws_kms_key.vault[0].key_id
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

resource "aws_cloudwatch_log_group" "vault" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/vault/${var.cluster_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "vault_audit" {
  count             = var.enable_audit_logging ? 1 : 0
  name              = "/aws/vault/${var.cluster_name}/audit"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-audit-logs"
    }
  )
}

# ============================================================================
# TLS Certificates (Self-Signed for Internal Use)
# ============================================================================

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.cluster_name} Vault CA"
    organization = "HashiCorp Vault"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature"
  ]
}

resource "tls_private_key" "vault" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vault" {
  private_key_pem = tls_private_key.vault.private_key_pem

  subject {
    common_name  = "vault.${var.cluster_name}.internal"
    organization = "HashiCorp Vault"
  }

  dns_names = [
    "vault.${var.cluster_name}.internal",
    "*.vault.${var.cluster_name}.internal",
    "localhost"
  ]

  ip_addresses = [
    "127.0.0.1"
  ]
}

resource "tls_locally_signed_cert" "vault" {
  cert_request_pem   = tls_cert_request.vault.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

# Store TLS certificates in S3 (avoids Secrets Manager permission issues).
# The S3 bucket is already KMS-encrypted and private.
resource "aws_s3_object" "vault_tls" {
  bucket  = aws_s3_bucket.vault_scripts.id
  key     = "tls/vault-tls.json"
  content = jsonencode({
    ca_cert     = tls_self_signed_cert.ca.cert_pem
    server_cert = tls_locally_signed_cert.vault.cert_pem
    server_key  = tls_private_key.vault.private_key_pem
  })
  etag = md5(jsonencode({
    ca_cert     = tls_self_signed_cert.ca.cert_pem
    server_cert = tls_locally_signed_cert.vault.cert_pem
    server_key  = tls_private_key.vault.private_key_pem
  }))

  tags = merge(
    var.additional_tags,
    {
      Name    = "${var.cluster_name}-vault-tls"
      Purpose = "vault-tls-certificates"
    }
  )
}

# ============================================================================
# S3 Bucket for Vault Install Script
# ============================================================================
# EC2 user-data is limited to 16 KB. The full Vault install script exceeds this
# limit, so we store the rendered script in S3 and use a tiny bootstrap in
# user-data that downloads and executes it at instance launch.

resource "aws_s3_bucket" "vault_scripts" {
  bucket_prefix = "${var.cluster_name}-vault-scripts-"
  force_destroy = true

  tags = merge(
    var.additional_tags,
    {
      Name    = "${var.cluster_name}-vault-scripts"
      Purpose = "vault-install-scripts"
    }
  )
}

resource "aws_s3_bucket_versioning" "vault_scripts" {
  bucket = aws_s3_bucket.vault_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_scripts" {
  bucket = aws_s3_bucket.vault_scripts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vault_scripts" {
  bucket                  = aws_s3_bucket.vault_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy allowing Vault instances to read scripts/TLS from S3 and write init creds
resource "aws_iam_role_policy" "vault_s3_scripts" {
  name = "${var.cluster_name}-s3-policy"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.vault_scripts.arn,
          "${aws_s3_bucket.vault_scripts.arn}/*"
        ]
      },
      {
        Sid    = "WriteInitCreds"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.vault_scripts.arn}/init/*"
        ]
      }
    ]
  })
}

# ============================================================================
# EC2 Instances for Vault Nodes
# ============================================================================

# Render the full Vault install script and upload it to S3.
# The rendered content is stored in S3 rather than passed directly as user-data
# to stay within the 16 KB EC2 user-data size limit.
# Generate per-node user-data scripts so each node knows its index (0=leader, 1+=follower)
locals {
  # S3 paths for TLS certs and init credentials
  tls_s3_uri  = "s3://${aws_s3_bucket.vault_scripts.id}/${aws_s3_object.vault_tls.key}"
  init_s3_uri = "s3://${aws_s3_bucket.vault_scripts.id}/init/vault-init.json"

  # Build a list of rendered user-data scripts, one per node
  vault_user_data_per_node = [
    for idx in range(var.vault_node_count) :
    templatefile("${path.module}/templates/user-data.sh.tpl", {
      cluster_name         = var.cluster_name
      vault_version        = var.vault_version
      vault_license        = var.vault_license
      region               = var.region
      kms_key_id           = var.enable_auto_unseal ? aws_kms_key.vault[0].id : ""
      enable_auto_unseal   = var.enable_auto_unseal
      tls_s3_bucket        = aws_s3_bucket.vault_scripts.id
      tls_s3_key           = aws_s3_object.vault_tls.key
      cloudwatch_log_group = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.vault[0].name : ""
      enable_cloudwatch    = var.enable_cloudwatch_logs
      audit_log_group      = var.enable_audit_logging ? aws_cloudwatch_log_group.vault_audit[0].name : ""
      enable_audit_logging = var.enable_audit_logging
      enable_auto_init     = var.enable_auto_init
      init_s3_bucket       = aws_s3_bucket.vault_scripts.id
      init_s3_key          = "init/vault-init.json"
      node_index           = idx
    })
  ]

  # Per-node tiny bootstrap scripts passed as EC2 user-data (<1 KB each).
  # Each bootstrap downloads the node-specific install script from S3 and executes it.
  # Node 0 gets vault-install-node-0.sh (initializes cluster), others get their own.
  vault_bootstrap_per_node = [
    for idx in range(var.vault_node_count) :
    <<-BOOTSTRAP
    #!/bin/bash
    exec > >(tee /var/log/user-data-bootstrap.log) 2>&1
    echo "=== Vault bootstrap for node ${idx} starting at $(date) ==="

    # Ensure AWS CLI is available (Ubuntu 22.04 includes it by default)
    if ! command -v aws &>/dev/null; then
      echo "Installing awscli..."
      apt-get update -y -qq
      apt-get install -y -qq awscli
    fi

    # Wait for IAM instance profile to propagate (can take 10-30s on new instances)
    echo "Waiting for IAM instance profile..."
    MAX_RETRIES=30
    for i in $(seq 1 $MAX_RETRIES); do
      if aws sts get-caller-identity --region "${var.region}" >/dev/null 2>&1; then
        echo "IAM credentials available (attempt $i)"
        break
      fi
      echo "Waiting for IAM credentials... ($i/$MAX_RETRIES)"
      sleep 10
    done

    echo "Downloading Vault install script for node ${idx} from S3..."
    DOWNLOAD_OK=false
    for i in $(seq 1 10); do
      if aws s3 cp "s3://${aws_s3_bucket.vault_scripts.id}/vault-install-node-${idx}.sh" \
        /tmp/vault-install.sh --region "${var.region}"; then
        DOWNLOAD_OK=true
        break
      fi
      echo "S3 download failed, retrying... ($i/10)"
      sleep 10
    done

    if [ "$DOWNLOAD_OK" != "true" ]; then
      echo "ERROR: Failed to download install script from S3 after 10 attempts"
      exit 1
    fi

    chmod +x /tmp/vault-install.sh

    echo "Executing Vault install script for node ${idx}..."
    exec bash /tmp/vault-install.sh
    BOOTSTRAP
  ]
}

# Upload per-node rendered install scripts to S3 (one per node index).
# Each script has a unique node_index so Node 0 initializes and others join.
resource "aws_s3_object" "vault_install_script" {
  count   = var.vault_node_count
  bucket  = aws_s3_bucket.vault_scripts.id
  key     = "vault-install-node-${count.index}.sh"
  content = local.vault_user_data_per_node[count.index]

  # Force replacement when the script content changes.
  etag = md5(local.vault_user_data_per_node[count.index])

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-install-node-${count.index}"
    }
  )
}

# NOTE: Data volumes are created inline on the aws_instance (ebs_block_device)
# rather than as separate aws_ebs_volume + aws_volume_attachment resources.
# This avoids creating duplicate unused EBS volumes.

# Vault EC2 instances
resource "aws_instance" "vault" {
  count                  = var.vault_node_count
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile   = aws_iam_instance_profile.vault.name
  # Bootstrap script downloads the node-specific install script from S3.
  # Each node gets its own script with the correct node_index baked in.
  user_data_base64 = base64encode(local.vault_bootstrap_per_node[count.index])

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.enable_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = var.enable_ebs_encryption
    delete_on_termination = true
  }

  # Data volume attached at launch time
  ebs_block_device {
    device_name           = "/dev/xvdf"
    volume_type           = var.data_volume_type
    volume_size           = var.data_volume_size
    iops                  = var.data_volume_type == "gp3" ? var.data_volume_iops : null
    throughput            = var.data_volume_type == "gp3" ? var.data_volume_throughput : null
    encrypted             = var.enable_ebs_encryption
    delete_on_termination = false
  }

  disable_api_termination = var.enable_termination_protection
  monitoring              = var.enable_detailed_monitoring

  # Propagate tags to inline EBS volumes so DLM snapshot policies can target them.
  # Without this, inline ebs_block_device volumes do NOT inherit instance tags,
  # and DLM target_tags won't match the data volumes.
  volume_tags = merge(
    var.additional_tags,
    {
      Name         = "${var.cluster_name}-vault-${count.index + 1}-data"
      VaultCluster = var.cluster_name
    }
  )

  tags = merge(
    var.additional_tags,
    {
      Name           = "${var.cluster_name}-vault-${count.index + 1}"
      VaultCluster   = var.cluster_name
      VaultAutoJoin  = "true"
      VaultNodeIndex = count.index + 1
    }
  )

  # Ensure NAT Gateways, routes, per-node S3 scripts are ready
  # before launching instances. The bootstrap user-data fetches the node-specific
  # script from S3, so all S3 objects must exist before any instance starts.
  depends_on = [
    aws_nat_gateway.main,
    aws_route.private_nat_gateway,
    aws_route_table_association.private,
    aws_s3_object.vault_install_script,
    aws_s3_object.vault_tls,
    aws_iam_role_policy.vault_s3_scripts,
  ]

  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}


# ============================================================================
# Network Load Balancer
# ============================================================================

resource "aws_lb" "vault" {
  name               = "${var.cluster_name}-vault-nlb"
  internal           = var.lb_internal
  load_balancer_type = "network"
  subnets            = var.lb_internal ? aws_subnet.private[*].id : aws_subnet.public[*].id

  enable_deletion_protection       = var.enable_deletion_protection_lb
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-nlb"
    }
  )
}

# Target group for Vault API (port 8200)
resource "aws_lb_target_group" "vault_api" {
  name     = "${var.cluster_name}-vault-api"
  port     = 8200
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = "/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200&drsecondarycode=200&performancestandbycode=200"
    port                = "8200"
    healthy_threshold   = 5
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  # NLB TCP target groups require healthy_threshold == unhealthy_threshold.
  # With threshold=5 and interval=30s, the NLB allows 150s (2.5 min) for
  # user-data to install Vault before marking targets unhealthy.
  # Targets show "initial" status during this window — this is normal NLB
  # behavior and will resolve once Vault starts responding on port 8200.
  deregistration_delay = 30

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-vault-api-tg"
    }
  )
}

# Register Vault instances with target group
resource "aws_lb_target_group_attachment" "vault_api" {
  count            = var.vault_node_count
  target_group_arn = aws_lb_target_group.vault_api.arn
  target_id        = aws_instance.vault[count.index].id
  port             = 8200
}

# Listener for Vault API
resource "aws_lb_listener" "vault_api" {
  load_balancer_arn = aws_lb.vault.arn
  port              = "8200"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault_api.arn
  }

  tags = var.additional_tags
}

# ============================================================================
# EBS Snapshot Lifecycle Policy
# ============================================================================

resource "aws_dlm_lifecycle_policy" "vault_snapshots" {
  count              = var.enable_ebs_snapshots ? 1 : 0
  description        = "Lifecycle policy for Vault data volume snapshots"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = var.snapshot_retention_days
      }

      tags_to_add = {
        SnapshotType = "automated"
        Cluster      = var.cluster_name
      }

      copy_tags = true
    }

    # DLM target_tags do NOT support wildcards. Use a tag that is set on
    # the instance (and inherited by inline ebs_block_device volumes).
    target_tags = {
      VaultCluster = var.cluster_name
    }
  }

  tags = merge(
    var.additional_tags,
    {
      Name = "${var.cluster_name}-snapshot-policy"
    }
  )
}

# IAM role for DLM
resource "aws_iam_role" "dlm" {
  count = var.enable_ebs_snapshots ? 1 : 0
  name  = "${var.cluster_name}-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = var.additional_tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count      = var.enable_ebs_snapshots ? 1 : 0
  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

