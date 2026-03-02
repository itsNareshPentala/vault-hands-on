# Vault Enterprise DR Lab for IBM Fyre

Complete solution for deploying a Vault Enterprise Disaster Recovery lab on IBM Fyre using manual VM provisioning with automated configuration.

## 🎯 Quick Overview

This lab deploys a production-ready Vault Enterprise DR setup with:
- **8 Individual VMs on IBM Fyre** (no clusters to create in Fyre)
- **2 Vault HA Groups**: Primary (3 VMs) + DR (3 VMs) - these form logical clusters via Vault's Raft consensus
- **2 Load Balancers**: HAProxy for each Vault group
- **TLS Encryption**: Auto-generated certificates
- **Auto-Unseal**: AWS KMS or Azure Key Vault
- **DR Replication**: Ready for disaster recovery testing

## 📝 Important Terminology

**In IBM Fyre:**
- You provision **8 individual VMs** (not clusters or stacks)
- Each VM is standalone - you request them one by one or in a batch
- No special "cluster" creation needed in Fyre

**In Vault:**
- A "cluster" means 3 Vault nodes working together using Raft consensus
- **Primary cluster** = 3 Vault VMs that form one logical Vault cluster
- **DR cluster** = 3 different Vault VMs that form another logical Vault cluster
- The clusters are created by Vault software, not by IBM Fyre

## 🚀 Quick Start (30 Minutes)

### Step 1: Provision 8 Individual VMs on IBM Fyre

Log in to https://fyre.ibm.com and request **8 separate VMs** (not clusters):

| VM Name | vCPU | RAM | Disk | OS | Purpose |
|---------|------|-----|------|-----|---------|
| vault-primary-1 | 4 | 8 GB | 100 GB | Ubuntu 22.04 | Primary Vault node 1 |
| vault-primary-2 | 4 | 8 GB | 100 GB | Ubuntu 22.04 | Primary Vault node 2 |
| vault-primary-3 | 4 | 8 GB | 100 GB | Ubuntu 22.04 | Primary Vault node 3 |
| vault-dr-1 | 4 | 8 GB | 100 GB | Ubuntu 22.04 | DR Vault node 1 |
| vault-dr-2 | 4 | 8 GB | 100 GB | Ubuntu 22.04 | DR Vault node 2 |
| vault-dr-3 | 4 | 8 GB | 100 GB | Ubuntu 22.04 | DR Vault node 3 |
| haproxy-primary | 2 | 4 GB | 50 GB | Ubuntu 22.04 | Load balancer for primary |
| haproxy-dr | 2 | 4 GB | 50 GB | Ubuntu 22.04 | Load balancer for DR |

**How to request in Fyre:**
1. Go to "Request Infrastructure" or "Create VMs"
2. Request 8 VMs with the specs above
3. Make sure all VMs are on the same network
4. Wait for provisioning (10-30 minutes)
5. Note down all 8 IP addresses

**You do NOT need to:**
- ❌ Create any "clusters" in Fyre
- ❌ Create any "stacks" in Fyre
- ❌ Configure any clustering in Fyre
- ✅ Just provision 8 individual VMs

### Step 2: Configure Deployment

```bash
# Create inventory file with your 8 VM IPs
cp inventory.txt.example inventory.txt
nano inventory.txt  # Add your actual IP addresses

# Create configuration file
cp config.env.example config.env
nano config.env  # Add Vault license and auto-unseal credentials
```

**Example inventory.txt:**
```bash
# These are just the 8 individual VM IPs from Fyre
PRIMARY_NODE_1_IP=10.16.23.45    # IP of vault-primary-1 VM
PRIMARY_NODE_2_IP=10.16.23.46    # IP of vault-primary-2 VM
PRIMARY_NODE_3_IP=10.16.23.47    # IP of vault-primary-3 VM
PRIMARY_LB_IP=10.16.23.48        # IP of haproxy-primary VM

DR_NODE_1_IP=10.16.23.49         # IP of vault-dr-1 VM
DR_NODE_2_IP=10.16.23.50         # IP of vault-dr-2 VM
DR_NODE_3_IP=10.16.23.51         # IP of vault-dr-3 VM
DR_LB_IP=10.16.23.52             # IP of haproxy-dr VM

SSH_USER=ubuntu
SSH_KEY_PATH=~/.ssh/fyre_key.pem
```

**Example config.env:**
```bash
VAULT_VERSION="1.21.1+ent"
VAULT_LICENSE="YOUR_VAULT_ENTERPRISE_LICENSE"

# AWS KMS Auto-Unseal
AUTO_UNSEAL_TYPE="awskms"
AWS_KMS_KEY_ID="arn:aws:kms:us-east-1:123456789012:key/your-key-id"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY="YOUR_AWS_ACCESS_KEY"
AWS_SECRET_KEY="YOUR_AWS_SECRET_KEY"
```

### Step 3: Deploy Everything

```bash
# Make script executable
chmod +x deploy-to-fyre.sh

# Run deployment
./deploy-to-fyre.sh
```

**Select option 6** (Full Deployment - All + Initialize)

The script will:
1. ✅ Generate TLS certificates
2. ✅ Install Vault on 6 VMs (3 primary + 3 DR)
3. ✅ Configure Vault nodes to form 2 logical clusters via Raft
4. ✅ Install HAProxy on 2 VMs
5. ✅ Initialize both Vault clusters
6. ✅ Display initialization keys (**SAVE THESE!**)

### Step 4: Verify Deployment

```bash
# Check primary Vault cluster (via load balancer)
export VAULT_ADDR="https://<PRIMARY_LB_IP>:8200"
export VAULT_SKIP_VERIFY=1
vault status

# Check DR Vault cluster (via load balancer)
export VAULT_ADDR="https://<DR_LB_IP>:8200"
vault status
```

Both should show:
- ✅ Initialized: true
- ✅ Sealed: false
- ✅ HA Enabled: true

## 📁 Project Structure

```
vault-dr-lab-fyre/
├── README.md                      # This file - start here
├── DEPLOYMENT-GUIDE.md            # Detailed deployment instructions
├── TEST-PLAN.md                   # Testing and validation procedures
├── deploy-to-fyre.sh              # Main deployment script ⭐
├── inventory.txt.example          # Template for VM IPs
├── config.env.example             # Template for configuration
├── scripts/
│   ├── install-vault.sh          # Vault installation script
│   └── configure-haproxy.sh      # HAProxy configuration script
└── templates/
    ├── vault.hcl.tpl             # Vault configuration template
    ├── haproxy.cfg.tpl           # HAProxy configuration template
    └── systemd-vault.service.tpl # Systemd service template
```

## 📚 Documentation

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **README.md** (this file) | Quick start and overview | Start here |
| **DEPLOYMENT-GUIDE.md** | Detailed step-by-step instructions | For manual deployment or troubleshooting |
| **TEST-PLAN.md** | Comprehensive testing procedures | After deployment for validation |

## 🏗️ Architecture Explained

```
┌─────────────────────────────────────────────────────────────┐
│              IBM Fyre - 8 Individual VMs                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────┐      ┌──────────────────────┐    │
│  │  Primary Vault Group │      │    DR Vault Group    │    │
│  │  (Logical Cluster)   │      │  (Logical Cluster)   │    │
│  │                      │      │                      │    │
│  │  ┌────────────────┐  │      │  ┌────────────────┐  │    │
│  │  │  HAProxy VM    │  │      │  │  HAProxy VM    │  │    │
│  │  │  (1 VM)        │  │      │  │  (1 VM)        │  │    │
│  │  └────────┬───────┘  │      │  └────────┬───────┘  │    │
│  │           │          │      │           │          │    │
│  │  ┌────────┴───────┐  │      │  ┌────────┴───────┐  │    │
│  │  │                │  │      │  │                │  │    │
│  │  │  Vault VM 1    │  │      │  │  Vault VM 1    │  │    │
│  │  │  Vault VM 2    │◄─┼──────┼─►│  Vault VM 2    │  │    │
│  │  │  Vault VM 3    │  │  DR  │  │  Vault VM 3    │  │    │
│  │  │  (3 VMs)       │  │ Repl │  │  (3 VMs)       │  │    │
│  │  │                │  │      │  │                │  │    │
│  │  │  Raft forms    │  │      │  │  Raft forms    │  │    │
│  │  │  logical       │  │      │  │  logical       │  │    │
│  │  │  cluster       │  │      │  │  cluster       │  │    │
│  │  └────────────────┘  │      │  └────────────────┘  │    │
│  └──────────────────────┘      └──────────────────────┘    │
│                                                               │
│  Total: 8 individual VMs (not Fyre clusters)                │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  AWS KMS / Azure KV    │
              │  (Auto-Unseal)         │
              └────────────────────────┘
```


┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL CLOUD SERVICES (AWS/Azure)                             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                           │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐                  │
│  │   AWS KMS        │    │  Azure Key Vault │    │   Azure AD       │                  │
│  │  (Auto-Unseal)   │    │  (Auto-Unseal)   │    │   (OIDC/JWT)     │                  │
│  │  Port: 443       │    │  Port: 443       │    │   Port: 443      │                  │
│  └────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘                  │
│           │                       │                       │                              │
└───────────┼───────────────────────┼───────────────────────┼──────────────────────────────┘
            │                       │                       │
            │                       │                       │
┌───────────┼───────────────────────┼───────────────────────┼──────────────────────────────┐
│           │         IBM FYRE INFRASTRUCTURE (8 VMs)       │                              │
├───────────┼───────────────────────┼───────────────────────┼──────────────────────────────┤
│           │                       │                       │                              │
│  ┌────────▼───────────────────────▼───────────────────────▼────────────────────┐        │
│  │                    EXTERNAL INTEGRATIONS                                     │        │
│  │  • LDAP Server (Port 636) - Internal Auth                                   │        │
│  │  • Oracle DB (Port 1521) - Dynamic Credentials                              │        │
│  │  • MSSQL DB (Port 1433) - Dynamic Credentials                               │        │
│  │  • Ansible Automation Platform (AAP) - Automation & Orchestration           │        │
│  └──────────────────────────────────────────────────────────────────────────────┘        │
│                                      │                                                   │
│                                      │ All Ports: 443, 636, 1521, 1433                  │
│                                      │                                                   │
│  ┌───────────────────────────────────┼──────────────────────────────────────────┐       │
│  │         PRIMARY CLUSTER           │              DR CLUSTER                  │       │
│  │      (Production Active)          │         (Disaster Recovery)              │       │
│  │                                   │                                          │       │
│  │  ┌─────────────────────┐          │          ┌─────────────────────┐        │       │
│  │  │   HAProxy LB        │          │          │   HAProxy LB        │        │       │
│  │  │   10.16.23.48       │◄─────────┼──────────►   10.16.23.52       │        │       │
│  │  │   2vCPU, 4GB RAM    │          │          │   2vCPU, 4GB RAM    │        │       │
│  │  │                     │          │          │                     │        │       │
│  │  │  Ports:             │          │          │  Ports:             │        │       │
│  │  │  • 8200 (API/UI)    │          │          │  • 8200 (API/UI)    │        │       │
│  │  │  • 8201 (Cluster)   │          │          │  • 8201 (Cluster)   │        │       │
│  │  │  • 8404 (Stats)     │          │          │  • 8404 (Stats)     │        │       │
│  │  └──────────┬──────────┘          │          └──────────┬──────────┘        │       │
│  │             │                     │                     │                    │       │
│  │    ┌────────┴────────┐            │            ┌────────┴────────┐          │       │
│  │    │                 │            │            │                 │          │       │
│  │  ┌─▼──────────┐  ┌──▼─────────┐  │  ┌────────▼──┐  ┌──────────▼─┐        │       │
│  │  │ Vault Node1│  │Vault Node2 │  │  │Vault Node1│  │Vault Node2 │        │       │
│  │  │10.16.23.45 │  │10.16.23.46 │  │  │10.16.23.49│  │10.16.23.50 │        │       │
│  │  │4vCPU,8GB   │  │4vCPU,8GB   │  │  │4vCPU,8GB  │  │4vCPU,8GB   │        │       │
│  │  └─────┬──────┘  └──────┬─────┘  │  └─────┬─────┘  └──────┬─────┘        │       │
│  │        │                │        │        │                │              │       │
│  │        │    ┌───────────▼──┐     │        │    ┌───────────▼──┐          │       │
│  │        │    │ Vault Node3  │     │        │    │ Vault Node3  │          │       │
│  │        │    │ 10.16.23.47  │     │        │    │ 10.16.23.51  │          │       │
│  │        │    │ 4vCPU, 8GB   │     │        │    │ 4vCPU, 8GB   │          │       │
│  │        │    └──────────────┘     │        │    └──────────────┘          │       │
│  │        │                         │        │                               │       │
│  │        └─────────┬───────────────┘        └────────┬──────────────────────┘       │
│  │                  │                                  │                              │
│  │         ┌────────▼──────────────────────────────────▼────────┐                    │
│  │         │         RAFT CONSENSUS & DR REPLICATION             │                    │
│  │         │         Port 8201 (Encrypted with mTLS)             │                    │
│  │         └─────────────────────────────────────────────────────┘                    │
│  └──────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              VAULT CONFIGURATION DETAILS                                 │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                           │
│  AUTHENTICATION BACKENDS:                    SECRETS ENGINES:                            │
│  ├─ LDAP (Internal) - Port 636              ├─ KV-v2 (Key-Value Store)                 │
│  ├─ OIDC/JWT (Azure AD) - Port 443          ├─ Transit (Encryption-as-a-Service)       │
│  ├─ AWS Auth - Port 443                     ├─ Azure Secrets Engine                    │
│  └─ Azure Auth - Port 443                   ├─ Database (Oracle) - Port 1521           │
│                                              └─ Database (MSSQL) - Port 1433            │
│                                                                                           │
│  ENTERPRISE FEATURES:                        SECURITY:                                   │
│  ├─ Active DR Replication                   ├─ TLS with Internal CA                    │
│  ├─ Namespaces                               ├─ mTLS for Replication                    │
│  ├─ Performance Replication                  ├─ Auto-Unseal (AWS KMS/Azure KV)          │
│  └─ Sentinel Policies                        └─ Certificate-based Node Auth             │
│                                                                                           │
│  STORAGE & HA:                               AUTOMATION:                                 │
│  ├─ Raft Integrated Storage                 ├─ Ansible Automation Platform (AAP)       │
│  ├─ 3-Node Quorum per Cluster               ├─ Automated Credential Rotation           │
│  ├─ Auto-Discovery (retry_join)             ├─ Automated Patching                      │
│  └─ Leader Election                          └─ Automated DR Failover/Switchover       │
│                                                                                           │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  TRAFFIC FLOWS                                           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                           │
│  1. CLIENT ACCESS:                                                                       │
│     Clients/AAP → HAProxy:8200 → Vault Nodes (Round-robin, Health-checked)             │
│                                                                                           │
│  2. RAFT CONSENSUS:                                                                      │
│     Vault Node ↔ Vault Node (Port 8201, mTLS encrypted)                                │
│                                                                                           │
│  3. DR REPLICATION:                                                                      │
│     Primary Cluster:8201 ↔ DR Cluster:8201 (Active DR, mTLS encrypted)                │
│                                                                                           │
│  4. AUTHENTICATION:                                                                      │
│     Vault → LDAP:636 (Internal users)                                                   │
│     Vault → Azure AD:443 (OIDC/JWT tokens)                                              │
│     Vault → AWS:443 (IAM authentication)                                                │
│     Vault → Azure:443 (Managed Identity auth)                                           │
│                                                                                           │
│  5. SECRETS MANAGEMENT:                                                                  │
│     Vault → Oracle:1521 (Dynamic credentials)                                           │
│     Vault → MSSQL:1433 (Dynamic credentials)                                            │
│     Vault → Azure:443 (Service Principal secrets)                                       │
│                                                                                           │
│  6. AUTO-UNSEAL:                                                                         │
│     Vault → AWS KMS:443 (Encryption key operations)                                     │
│     Vault → Azure Key Vault:443 (Encryption key operations)                             │
│                                                                                           │
│  7. AUTOMATION:                                                                          │
│     AAP → Vault:8200 (API calls for automation)                                         │
│     AAP → Vault Nodes (SSH for patching)                                                │
│                                                                                           │
└─────────────────────────────────────────────────────────────────────────────────────────┘


**Key Points:**
- IBM Fyre: You provision **8 individual VMs** (no clustering in Fyre)
- Vault Software: Creates **2 logical clusters** using Raft consensus protocol
- Each logical cluster has **3 Vault VMs** working together
- HAProxy: **1 VM per cluster** for load balancing

## 🔧 What the Deployment Script Does

The `deploy-to-fyre.sh` script:

1. **Connects to your 8 VMs** via SSH
2. **Installs Vault** on 6 VMs (3 primary + 3 DR)
3. **Configures Raft** so 3 VMs form a logical cluster
4. **Installs HAProxy** on 2 VMs
5. **Initializes** both Vault clusters
6. **Sets up DR replication** between the two clusters

**You don't need to:**
- ❌ Manually create clusters
- ❌ Configure Raft yourself
- ❌ Set up networking between nodes
- ✅ Just run the script!

## 🎯 Use Cases

Perfect for:
- **Performance Testing**: Identify Vault bottlenecks
- **DR Testing**: Practice failover/switchover procedures
- **Training**: Learn Vault Enterprise DR features
- **POC/Demo**: Demonstrate Vault DR to customers
- **Development**: Test applications against Vault DR

## 🔐 Security Features

- ✅ TLS encryption for all communication
- ✅ Auto-unseal with AWS KMS or Azure Key Vault
- ✅ High availability with Raft consensus
- ✅ DR replication for disaster recovery
- ✅ Systemd service hardening
- ✅ Certificate-based authentication

## 📊 Resource Requirements

| Component | Count | Total vCPU | Total RAM | Total Disk |
|-----------|-------|------------|-----------|------------|
| Vault VMs | 6 | 24 | 48 GB | 600 GB |
| HAProxy VMs | 2 | 4 | 8 GB | 100 GB |
| **Total VMs** | **8** | **28** | **56 GB** | **700 GB** |

## 🔄 DR Replication Setup

After deployment, the script automatically configures DR replication between the two Vault clusters.

To verify:

```bash
# Check primary cluster
export VAULT_ADDR="https://<PRIMARY_LB_IP>:8200"
export VAULT_TOKEN="<root_token>"
vault read sys/replication/dr/status

# Check DR cluster
export VAULT_ADDR="https://<DR_LB_IP>:8200"
export VAULT_TOKEN="<dr_root_token>"
vault read sys/replication/dr/status
```

## 🌐 Access Points

After deployment:

| Service | URL | Credentials |
|---------|-----|-------------|
| Primary Vault UI | `https://<PRIMARY_LB_IP>:8200/ui` | Root token |
| DR Vault UI | `https://<DR_LB_IP>:8200/ui` | Root token |
| Primary HAProxy Stats | `http://<PRIMARY_LB_IP>:8404` | admin/admin |
| DR HAProxy Stats | `http://<DR_LB_IP>:8404` | admin/admin |

## 🐛 Troubleshooting

### Vault won't start
```bash
ssh <node_ip>
sudo journalctl -u vault -f
```

### Auto-unseal failing
- Verify AWS/Azure credentials in `config.env`
- Check KMS key permissions
- Verify network connectivity to AWS/Azure

### HAProxy health checks failing
- Check Vault is running: `sudo systemctl status vault`
- Verify ports 8200, 8201 are accessible
- Check HAProxy logs: `sudo journalctl -u haproxy -f`

### Can't connect to Vault
- Verify firewall rules allow ports 8200, 8201
- Check TLS certificates are valid
- Verify load balancer is running

## 📈 Next Steps

After deployment:

1. **Enable Authentication**: Configure LDAP, OIDC, or AppRole
2. **Enable Secrets Engines**: KV, Database, PKI, Transit
3. **Create Policies**: Define access control policies
4. **Test DR Scenarios**: Practice failover/switchover
5. **Run Performance Tests**: Identify bottlenecks
6. **Monitor**: Set up metrics and logging

See [`TEST-PLAN.md`](TEST-PLAN.md:1) for comprehensive testing procedures.

## 🧹 Clean Up

To remove the deployment:

```bash
# Stop all services on the 8 VMs
for ip in $PRIMARY_NODE_1_IP $PRIMARY_NODE_2_IP $PRIMARY_NODE_3_IP \
          $DR_NODE_1_IP $DR_NODE_2_IP $DR_NODE_3_IP; do
  ssh $SSH_USER@$ip "sudo systemctl stop vault"
done

for ip in $PRIMARY_LB_IP $DR_LB_IP; do
  ssh $SSH_USER@$ip "sudo systemctl stop haproxy"
done

# Delete the 8 VMs from IBM Fyre portal
```

## 📖 Additional Resources

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault DR Replication](https://www.vaultproject.io/docs/enterprise/replication)
- [Raft Storage Backend](https://www.vaultproject.io/docs/configuration/storage/raft)
- [Auto-Unseal](https://www.vaultproject.io/docs/concepts/seal)

## ⚠️ Important Notes

- **IBM Fyre**: You provision **8 individual VMs**, not clusters or stacks
- **Vault Clusters**: Created by Vault software using Raft, not by Fyre
- **Save initialization keys**: Store them securely - you'll need them for recovery
- **Network**: Ensure all 8 VMs can communicate on ports 8200, 8201
- **Auto-unseal**: Requires AWS KMS or Azure Key Vault access
- **License**: Valid Vault Enterprise license required

## ❓ FAQ

**Q: Do I need to create clusters in IBM Fyre?**
A: No! You just provision 8 individual VMs. Vault software creates the logical clusters.

**Q: What's a "primary cluster"?**
A: It's 3 Vault VMs working together using Raft consensus. Not a Fyre concept.

**Q: Do I need to configure Raft?**
A: No! The deployment script does this automatically.

**Q: Can I use fewer VMs?**
A: For testing, yes. Minimum is 2 VMs (1 Vault + 1 HAProxy), but you lose HA and DR.

---

**Ready to deploy?** Follow the Quick Start section above or see [`DEPLOYMENT-GUIDE.md`](DEPLOYMENT-GUIDE.md:1) for detailed instructions.