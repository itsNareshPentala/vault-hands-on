# End-to-End Test Plan for Vault DR Lab

## Test Environment Requirements

### Prerequisites Checklist
- [ ] IBM Fyre OpenStack access with credentials
- [ ] Vault Enterprise license (valid)
- [ ] AWS KMS key or Azure Key Vault configured
- [ ] Terraform >= 1.5.0 installed
- [ ] OpenStack CLI installed (optional, for verification)
- [ ] SSH client
- [ ] Vault CLI >= 1.21.0

## Phase 1: Pre-Deployment Validation

### 1.1 Terraform Configuration Test
```bash
cd vault-dr-lab-fyre

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format check
terraform fmt -check -recursive

# Expected: All checks pass
```

### 1.2 Dry Run (Plan)
```bash
# Create test terraform.tfvars
cp terraform.tfvars.example terraform.tfvars

# Edit with test values (use minimal resources for testing)
# Set assign_floating_ips = false to avoid public IP costs

# Run plan without applying
terraform plan -out=test.tfplan

# Expected: Plan shows 40+ resources to be created
# - 1 network (or use existing)
# - 1 subnet
# - 8 ports (2 LB + 6 Vault)
# - 2 security groups
# - 6 Vault VMs
# - 2 Load balancer VMs
# - 6 data volumes
# - TLS certificates
# - etc.
```

### 1.3 Resource Count Verification
```bash
terraform plan | grep "Plan:"

# Expected output similar to:
# Plan: 45 to add, 0 to change, 0 to destroy
```

## Phase 2: Deployment Test

### 2.1 Deploy Infrastructure
```bash
# Apply with auto-approve for testing
terraform apply -auto-approve

# Monitor deployment (typically 10-15 minutes)
# Watch for:
# - Network creation
# - Security group creation
# - VM provisioning
# - Volume attachments
# - User data execution (Vault installation)
```

### 2.2 Verify Deployment
```bash
# Check Terraform state
terraform state list

# Get outputs
terraform output

# Expected outputs:
# - primary_cluster (with IPs and URLs)
# - dr_cluster (with IPs and URLs)
# - connection_info (formatted guide)
```

## Phase 3: Infrastructure Validation

### 3.1 Network Connectivity Test
```bash
# Get primary cluster IPs
PRIMARY_LB_IP=$(terraform output -json | jq -r '.primary_cluster.value.load_balancer.private_ip')
PRIMARY_NODE1_IP=$(terraform output -json | jq -r '.primary_cluster.value.nodes.private_ips[0]')

# Test SSH connectivity
ssh -i vault-key.pem ubuntu@$PRIMARY_NODE1_IP "echo 'SSH OK'"

# Test network connectivity between nodes
ssh -i vault-key.pem ubuntu@$PRIMARY_NODE1_IP "ping -c 3 $PRIMARY_LB_IP"
```

### 3.2 Vault Service Status Check
```bash
# Check Vault service on all nodes
for i in {0..2}; do
  NODE_IP=$(terraform output -json | jq -r ".primary_cluster.value.nodes.private_ips[$i]")
  echo "Checking Vault on node $((i+1)): $NODE_IP"
  ssh -i vault-key.pem ubuntu@$NODE_IP "sudo systemctl status vault --no-pager"
done

# Expected: All services should be "active (running)"
```

### 3.3 HAProxy Status Check
```bash
# Check HAProxy on load balancers
LB_IP=$(terraform output -json | jq -r '.primary_cluster.value.load_balancer.private_ip')
ssh -i vault-key.pem ubuntu@$LB_IP "sudo systemctl status haproxy --no-pager"

# Check HAProxy stats page (if enabled)
STATS_URL=$(terraform output -json | jq -r '.primary_cluster.value.load_balancer.stats_url')
curl -u admin:password $STATS_URL
```

## Phase 4: Vault Functionality Test

### 4.1 Initialize Primary Cluster
```bash
# SSH to primary node 1
PRIMARY_NODE1=$(terraform output -json | jq -r '.primary_cluster.value.nodes.private_ips[0]')
ssh -i vault-key.pem ubuntu@$PRIMARY_NODE1

# Set Vault address
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=1

# Initialize Vault
vault operator init -key-shares=5 -key-threshold=3 > init-keys.txt

# Save unseal keys and root token
cat init-keys.txt

# Unseal Vault (should auto-unseal with AWS KMS/Azure KV)
vault status

# Expected: Sealed = false (if auto-unseal works)
```

### 4.2 Verify Auto-Unseal
```bash
# Check seal status
vault status | grep "Seal Type"

# Expected: "Seal Type: awskms" or "Seal Type: azurekeyvault"

# Verify unsealed
vault status | grep "Sealed"

# Expected: "Sealed: false"
```

### 4.3 Test Vault API via Load Balancer
```bash
# From local machine or jump host
LB_IP=$(terraform output -json | jq -r '.primary_cluster.value.load_balancer.private_ip')

# Test Vault API through load balancer
curl -k https://$LB_IP:8200/v1/sys/health

# Expected: JSON response with "initialized": true, "sealed": false
```

### 4.4 Verify Raft Cluster
```bash
# Login to Vault
vault login <root-token>

# Check Raft peers
vault operator raft list-peers

# Expected: 3 peers listed (all primary nodes)
```

## Phase 5: DR Cluster Test

### 5.1 Initialize DR Cluster
```bash
# SSH to DR node 1
DR_NODE1=$(terraform output -json | jq -r '.dr_cluster.value.nodes.private_ips[0]')
ssh -i vault-key.pem ubuntu@$DR_NODE1

# Initialize DR cluster
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=1
vault operator init -key-shares=5 -key-threshold=3 > dr-init-keys.txt

# Verify unsealed
vault status
```

### 5.2 Configure DR Replication
```bash
# On PRIMARY cluster
vault login <primary-root-token>

# Enable DR primary
vault write -f sys/replication/dr/primary/enable

# Generate DR secondary token
vault write sys/replication/dr/primary/secondary-token id=dr-secondary

# Copy the wrapping_token value

# On DR cluster
vault login <dr-root-token>

# Enable DR secondary
vault write sys/replication/dr/secondary/enable token=<wrapping-token>

# Check replication status
vault read sys/replication/dr/status
```

### 5.3 Verify DR Replication
```bash
# On PRIMARY
vault read sys/replication/dr/status

# Expected: mode = "primary", state = "stream-wals"

# On DR
vault read sys/replication/dr/status

# Expected: mode = "secondary", state = "stream-wals"
```

## Phase 6: Use Case Validation

### 6.1 Enable Authentication Methods
```bash
# On primary cluster
vault auth enable ldap
vault auth enable oidc
vault auth enable aws
vault auth enable azure

# Verify
vault auth list
```

### 6.2 Enable Secrets Engines
```bash
# Enable KV-v2
vault secrets enable -path=secret kv-v2

# Enable Transit
vault secrets enable transit

# Enable Azure secrets
vault secrets enable azure

# Enable Database secrets
vault secrets enable database

# Verify
vault secrets list
```

### 6.3 Test Secrets Operations
```bash
# Write a secret
vault kv put secret/test password=mypassword

# Read the secret
vault kv get secret/test

# Expected: password = mypassword
```

### 6.4 Enable Namespaces
```bash
# Create namespace
vault namespace create test-ns

# List namespaces
vault namespace list

# Expected: test-ns listed
```

## Phase 7: Performance Testing

### 7.1 Basic Performance Test
```bash
# Install vault-benchmark
go install github.com/hashicorp/vault-benchmark@latest

# Run basic benchmark
vault-benchmark run \
  -address=https://$LB_IP:8200 \
  -token=$VAULT_TOKEN \
  -duration=60s \
  -workers=10

# Monitor metrics
```

### 7.2 Prometheus Metrics Check
```bash
# Check Vault metrics endpoint
curl -k https://$PRIMARY_NODE1:8200/v1/sys/metrics?format=prometheus

# Expected: Prometheus-formatted metrics
```

## Phase 8: DR Operations Test

### 8.1 DR Promotion Test
```bash
# Simulate primary failure
# Promote DR to primary
vault write -f sys/replication/dr/secondary/promote

# Verify new primary
vault read sys/replication/dr/status

# Expected: mode = "primary"
```

### 8.2 DR Demotion/Switchover Test
```bash
# Demote back to secondary
vault write -f sys/replication/dr/secondary/demote

# Re-enable as secondary
vault write sys/replication/dr/secondary/enable token=<new-token>
```

## Phase 9: Cleanup Test

### 9.1 Destroy Infrastructure
```bash
# Destroy all resources
terraform destroy -auto-approve

# Verify cleanup
terraform state list

# Expected: No resources remaining
```

## Test Success Criteria

### ✅ All Tests Pass If:
1. Terraform init/validate/plan succeed
2. All 8 VMs provision successfully
3. Vault services start on all nodes
4. HAProxy services start on load balancers
5. Auto-unseal works (Vault unseals automatically)
6. Raft cluster forms with 3 peers per cluster
7. DR replication establishes successfully
8. All authentication methods enable
9. All secrets engines enable
10. Secrets can be written and read
11. Namespaces can be created
12. DR promotion/demotion works
13. Terraform destroy completes cleanly

## Troubleshooting Guide

### Common Issues

**Issue**: Terraform init fails
- **Solution**: Check OpenStack credentials, verify network connectivity

**Issue**: VM provisioning fails
- **Solution**: Check quotas, verify image/flavor availability

**Issue**: Vault service won't start
- **Solution**: Check logs with `journalctl -u vault -f`, verify license

**Issue**: Auto-unseal fails
- **Solution**: Verify AWS KMS/Azure KV credentials, check network access

**Issue**: Raft cluster won't form
- **Solution**: Check network connectivity between nodes, verify ports 8200/8201

**Issue**: DR replication fails
- **Solution**: Verify network connectivity between clusters, check token validity

## Estimated Test Duration

- **Phase 1-2 (Deployment)**: 15-20 minutes
- **Phase 3-4 (Validation)**: 10-15 minutes
- **Phase 5 (DR Setup)**: 10-15 minutes
- **Phase 6 (Use Cases)**: 15-20 minutes
- **Phase 7 (Performance)**: 10-15 minutes
- **Phase 8 (DR Ops)**: 10-15 minutes
- **Phase 9 (Cleanup)**: 5-10 minutes

**Total**: ~90-120 minutes for complete end-to-end test

## Test Report Template

```
# Vault DR Lab Test Report

Date: ___________
Tester: ___________
Environment: IBM Fyre

## Results Summary
- Deployment: [ ] PASS [ ] FAIL
- Vault Initialization: [ ] PASS [ ] FAIL
- Auto-Unseal: [ ] PASS [ ] FAIL
- Raft Cluster: [ ] PASS [ ] FAIL
- DR Replication: [ ] PASS [ ] FAIL
- Use Cases: [ ] PASS [ ] FAIL
- Performance: [ ] PASS [ ] FAIL
- DR Operations: [ ] PASS [ ] FAIL

## Issues Encountered:
1. ___________
2. ___________

## Recommendations:
1. ___________
2. ___________

## Overall Status: [ ] PASS [ ] FAIL