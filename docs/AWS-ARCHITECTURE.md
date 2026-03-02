# Vault Enterprise DR on AWS - Architecture Design

## Overview

This architecture implements a production-ready Vault Enterprise Disaster Recovery setup on AWS, following HashiCorp Validated Designs principles.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS MULTI-REGION DEPLOYMENT                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────────────────────────┐  ┌──────────────────────────────────┐ │
│  │   PRIMARY REGION (us-east-1)     │  │     DR REGION (us-east-2)        │ │
│  │                                   │  │                                  │ │
│  │  ┌────────────────────────────┐  │  │  ┌────────────────────────────┐ │ │
│  │  │  VPC: 10.0.0.0/16          │  │  │  │  VPC: 10.1.0.0/16          │ │ │
│  │  │                            │  │  │  │                            │ │ │
│  │  │  ┌──────────────────────┐  │  │  │  │  ┌──────────────────────┐ │ │ │
│  │  │  │  Public Subnets      │  │  │  │  │  │  Public Subnets      │ │ │ │
│  │  │  │  - 10.0.1.0/24 (AZ-a)│  │  │  │  │  │  - 10.1.1.0/24 (AZ-a)│ │ │ │
│  │  │  │  - 10.0.2.0/24 (AZ-b)│  │  │  │  │  │  - 10.1.2.0/24 (AZ-b)│ │ │ │
│  │  │  │  - 10.0.3.0/24 (AZ-c)│  │  │  │  │  │  - 10.1.3.0/24 (AZ-c)│ │ │ │
│  │  │  │                      │  │  │  │  │  │                      │ │ │ │
│  │  │  │  ┌────────────────┐  │  │  │  │  │  │  ┌────────────────┐ │ │ │ │
│  │  │  │  │  NLB (Primary) │  │  │  │  │  │  │  │  NLB (DR)      │ │ │ │ │
│  │  │  │  │  Port: 8200    │  │  │  │  │  │  │  │  Port: 8200    │ │ │ │ │
│  │  │  │  └────────┬───────┘  │  │  │  │  │  │  └────────┬───────┘ │ │ │ │
│  │  │  └───────────┼──────────┘  │  │  │  │  └───────────┼──────────┘ │ │ │
│  │  │              │             │  │  │  │              │             │ │ │
│  │  │  ┌───────────▼──────────┐  │  │  │  │  ┌───────────▼──────────┐ │ │ │
│  │  │  │  Private Subnets     │  │  │  │  │  │  Private Subnets     │ │ │ │
│  │  │  │  - 10.0.11.0/24 (AZ-a)│ │  │  │  │  │  - 10.1.11.0/24 (AZ-a)│ │ │
│  │  │  │  - 10.0.12.0/24 (AZ-b)│ │  │  │  │  │  - 10.1.12.0/24 (AZ-b)│ │ │
│  │  │  │  - 10.0.13.0/24 (AZ-c)│ │  │  │  │  │  - 10.1.13.0/24 (AZ-c)│ │ │
│  │  │  │                      │  │  │  │  │  │                      │ │ │ │
│  │  │  │  ┌────────────────┐  │  │  │  │  │  │  ┌────────────────┐ │ │ │ │
│  │  │  │  │ Vault Node 1   │  │  │  │  │  │  │  │ Vault Node 1   │ │ │ │ │
│  │  │  │  │ t3.xlarge      │  │  │  │  │  │  │  │ t3.xlarge      │ │ │ │ │
│  │  │  │  │ AZ-a           │  │  │  │  │  │  │  │ AZ-a           │ │ │ │ │
│  │  │  │  └────────────────┘  │  │  │  │  │  │  └────────────────┘ │ │ │ │
│  │  │  │  ┌────────────────┐  │  │  │  │  │  │  ┌────────────────┐ │ │ │ │
│  │  │  │  │ Vault Node 2   │  │  │  │  │  │  │  │ Vault Node 2   │ │ │ │ │
│  │  │  │  │ t3.xlarge      │  │  │  │  │  │  │  │ t3.xlarge      │ │ │ │ │
│  │  │  │  │ AZ-b           │  │  │  │  │  │  │  │ AZ-b           │ │ │ │ │
│  │  │  │  └────────────────┘  │  │  │  │  │  │  └────────────────┘ │ │ │ │
│  │  │  │  ┌────────────────┐  │  │  │  │  │  │  ┌────────────────┐ │ │ │ │
│  │  │  │  │ Vault Node 3   │  │  │  │  │  │  │  │ Vault Node 3   │ │ │ │ │
│  │  │  │  │ t3.xlarge      │  │  │  │  │  │  │  │ t3.xlarge      │ │ │ │ │
│  │  │  │  │ AZ-c           │  │  │  │  │  │  │  │ AZ-c           │ │ │ │ │
│  │  │  │  └────────────────┘  │  │  │  │  │  │  └────────────────┘ │ │ │ │
│  │  │  └──────────────────────┘  │  │  │  └──────────────────────┘ │ │ │
│  │  └────────────────────────────┘  │  │  └────────────────────────┘ │ │
│  │                                   │  │                            │ │
│  │  ┌────────────────────────────┐  │  │  ┌────────────────────────┐ │ │
│  │  │  AWS KMS (us-east-1)       │  │  │  │  AWS KMS (us-east-2)   │ │ │
│  │  │  - Auto-unseal key         │  │  │  │  - Auto-unseal key     │ │ │
│  │  └────────────────────────────┘  │  │  └────────────────────────┘ │ │
│  └───────────────┬───────────────────┘  └───────────────┬────────────┘ │
│                  │                                       │              │
│                  └───────────────────┬───────────────────┘              │
│                                      │                                  │
│                          ┌───────────▼──────────┐                       │
│                          │  DR Replication      │                       │
│                          │  (Port 8201, mTLS)   │                       │
│                          └──────────────────────┘                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Network Architecture

#### Primary Region (us-east-1)
- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 3 subnets across 3 AZs (for NLB)
  - 10.0.1.0/24 (us-east-1a)
  - 10.0.2.0/24 (us-east-1b)
  - 10.0.3.0/24 (us-east-1c)
- **Private Subnets**: 3 subnets across 3 AZs (for Vault nodes)
  - 10.0.11.0/24 (us-east-1a)
  - 10.0.12.0/24 (us-east-1b)
  - 10.0.13.0/24 (us-east-1c)

#### DR Region (us-east-2)
- **VPC CIDR**: 10.1.0.0/16
- **Public Subnets**: 3 subnets across 3 AZs
  - 10.1.1.0/24 (us-east-2a)
  - 10.1.2.0/24 (us-east-2b)
  - 10.1.3.0/24 (us-east-2c)
- **Private Subnets**: 3 subnets across 3 AZs
  - 10.1.11.0/24 (us-east-2a)
  - 10.1.12.0/24 (us-east-2b)
  - 10.1.13.0/24 (us-east-2c)

### 2. Compute Resources

#### Vault Nodes (6 total: 3 Primary + 3 DR)
- **Instance Type**: t3.xlarge
  - 4 vCPU
  - 16 GB RAM (exceeds 8GB requirement for headroom)
  - EBS Optimized
- **OS**: Ubuntu 22.04 LTS
- **Storage**: 
  - Root: 50 GB gp3
  - Data: 100 GB gp3 (for Raft storage)
- **Distribution**: One node per AZ for HA

#### Load Balancers (2 total: 1 Primary + 1 DR)
- **Type**: Network Load Balancer (NLB)
- **Scheme**: Internal (private)
- **Cross-Zone**: Enabled
- **Ports**: 8200 (API/UI), 8201 (Cluster)

### 3. Security

#### Security Groups

**Vault Nodes Security Group**
- Inbound:
  - Port 8200 (HTTPS) from NLB
  - Port 8201 (Cluster) from other Vault nodes
  - Port 8201 (DR Replication) from DR region CIDR
  - Port 22 (SSH) from bastion/admin CIDR
- Outbound:
  - All traffic (for KMS, updates, etc.)

**NLB Security Group**
- Inbound:
  - Port 8200 from application CIDR
  - Port 443 from application CIDR (if using HTTPS)
- Outbound:
  - Port 8200 to Vault nodes

#### IAM Roles

**Vault Instance Role**
- KMS permissions:
  - `kms:Encrypt`
  - `kms:Decrypt`
  - `kms:DescribeKey`
- EC2 permissions (for auto-discovery):
  - `ec2:DescribeInstances`
- CloudWatch Logs:
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`

### 4. Storage

#### Raft Integrated Storage
- **Backend**: Raft (integrated storage)
- **Storage**: EBS gp3 volumes (100 GB per node)
- **Snapshots**: Automated daily snapshots
- **Encryption**: EBS encryption enabled

### 5. Auto-Unseal

#### AWS KMS
- **Primary Region**: KMS key in us-east-1
- **DR Region**: KMS key in us-east-2
- **Key Policy**: Allows Vault IAM role to use key
- **Rotation**: Automatic annual rotation enabled

### 6. High Availability

#### Raft Consensus
- 3-node cluster per region
- Quorum: 2 nodes required
- Leader election automatic
- Auto-discovery via AWS tags

#### Load Balancing
- NLB health checks on port 8200
- Unhealthy threshold: 2 consecutive failures
- Healthy threshold: 2 consecutive successes
- Interval: 10 seconds

### 7. Disaster Recovery

#### DR Replication
- **Type**: Active DR replication
- **Direction**: Primary (us-east-1) → DR (us-east-2)
- **Protocol**: mTLS encrypted
- **Port**: 8201
- **Latency**: Cross-region (typically 60-100ms)

#### Failover Strategy
1. Promote DR cluster to primary
2. Update DNS/application endpoints
3. Verify replication status
4. Test application connectivity

### 8. Monitoring & Logging

#### CloudWatch Metrics
- CPU utilization
- Memory utilization
- Disk I/O
- Network throughput
- Vault-specific metrics (via CloudWatch agent)

#### CloudWatch Logs
- Vault audit logs
- Vault operational logs
- System logs

#### Alarms
- High CPU (>80%)
- High memory (>90%)
- Disk space low (<20%)
- Vault sealed
- Replication lag

## Resource Sizing

### Cost Estimation (Monthly)

**Primary Region (us-east-1)**
- 3x t3.xlarge instances: ~$300
- 3x 100GB gp3 volumes: ~$30
- NLB: ~$20
- KMS: ~$1
- Data transfer: ~$50
- **Subtotal**: ~$401/month

**DR Region (us-east-2)**
- 3x t3.xlarge instances: ~$300
- 3x 100GB gp3 volumes: ~$30
- NLB: ~$20
- KMS: ~$1
- Data transfer: ~$50
- **Subtotal**: ~$401/month

**Total Estimated Cost**: ~$802/month

## Deployment Phases

### Phase 1: Network Infrastructure
- Create VPCs in both regions
- Create subnets (public + private)
- Configure Internet Gateways
- Configure NAT Gateways
- Set up route tables
- Configure VPC peering (for DR replication)

### Phase 2: Security
- Create security groups
- Create IAM roles and policies
- Create KMS keys
- Generate TLS certificates

### Phase 3: Compute
- Launch Vault EC2 instances
- Attach EBS volumes
- Configure user data for Vault installation
- Create NLBs
- Configure target groups

### Phase 4: Vault Configuration
- Initialize primary cluster
- Configure Raft storage
- Enable auto-unseal
- Initialize DR cluster
- Configure DR replication

### Phase 5: Monitoring
- Set up CloudWatch dashboards
- Configure alarms
- Enable audit logging
- Set up log aggregation

## HashiCorp Validated Design Compliance

This architecture follows HashiCorp Validated Designs:

✅ **Multi-AZ Deployment**: Nodes distributed across 3 AZs
✅ **Raft Integrated Storage**: No external storage dependencies
✅ **Auto-Unseal**: AWS KMS integration
✅ **Load Balancing**: NLB for high availability
✅ **DR Replication**: Multi-region active DR
✅ **Security**: TLS encryption, IAM roles, security groups
✅ **Monitoring**: CloudWatch integration
✅ **Scalability**: Can add nodes without downtime
✅ **Backup**: Automated snapshots

## Differences from vCenter Implementation

| Aspect | vCenter (Original) | AWS (New) |
|--------|-------------------|-----------|
| Infrastructure | Equinix Metal bare metal | AWS EC2 instances |
| Networking | VLAN-based | VPC with subnets |
| Storage | NFS shared storage | EBS volumes with Raft |
| Load Balancer | HAProxy on VM | AWS NLB (managed) |
| Auto-Unseal | Manual (Shamir) | AWS KMS |
| DR | Single location | Multi-region |
| HA | 2 ESXi hosts | 3 AZs per region |
| Management | Manual VM provisioning | Terraform automation |

## Next Steps

1. Implement Terraform modules for each phase
2. Create deployment scripts
3. Set up CI/CD pipeline
4. Document operational procedures
5. Create runbooks for common scenarios