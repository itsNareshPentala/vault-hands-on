# Vault Enterprise DR Replication Testing Guide

**Date:** March 2026
**Environment:** AWS (Primary: us-east-1, DR: us-east-2)

---

## Prerequisites

- Vault Enterprise deployed with primary and DR clusters
- DR replication enabled via Vault UI
- Root token available (from auto-init S3 credentials)
- `vault` CLI and `aws` CLI installed locally
- Network access to both NLB endpoints

### Retrieve Cluster Endpoints
terraform output -json vault_init_secrets | jq .
terraform output -json vault_init_secrets | jq -r '.retrieve_primary_cmd'

```bash
terraform output -json primary_cluster | jq -r '.load_balancer.url'
terraform output -json dr_cluster | jq -r '.load_balancer.url'
```

### Retrieve Root Token

```bash
# Primary cluster
aws s3 cp s3://<primary-scripts-bucket>/init/vault-init.json - --region us-east-1 | jq .

# DR cluster
aws s3 cp s3://<dr-scripts-bucket>/init/vault-init.json - --region us-east-2 | jq .
```

Get the exact bucket names from:

```bash
terraform output -json vault_init_secrets | jq .
```

---

## Step 1 — Verify Replication Status

### 1.1 Check Primary Cluster

```bash
export VAULT_ADDR="$(terraform output -json primary_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault login <root_token>
vault read sys/replication/dr/status
```

**Expected output:**

| Field | Expected Value |
|-------|---------------|
| `mode` | `primary` |
| `state` | `running` |
| `cluster_id` | (UUID) |

### 1.2 Check DR Cluster

```bash
export VAULT_ADDR="$(terraform output -json dr_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault read sys/replication/dr/status
```

**Expected output:**

| Field | Expected Value |
|-------|---------------|
| `mode` | `secondary` |
| `state` | `stream-wals` |

> If `state` is `merkle-diff` or `merkle-sync`, replication is still catching up. Wait a few minutes and check again.

---

## Step 2 — Write Test Data on Primary

```bash
export VAULT_ADDR="$(terraform output -json primary_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault login <root_token>

# Enable KV v2 secrets engine
vault secrets enable -path=secret kv-v2

# Write test secret
vault kv put secret/dr-test \
  message="hello-from-primary" \
  timestamp="$(date -u)" \
  environment="dr-test"

# Verify the write
vault kv get secret/dr-test
```

**Expected:** Secret is created and readable on the primary.

---

## Step 3 — Simulate Failover (Promote DR to Primary)

This simulates a disaster scenario where the primary cluster is unavailable and the DR cluster needs to take over.

### 3.1 Generate a DR Operation Token

Run this on the **primary** cluster (while it's still available):

```bash
export VAULT_ADDR="$(terraform output -json primary_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

# Initialize the DR operation token generation
vault operator generate-root -dr-token -init
```

**Save the output values:**
- `Nonce` — needed for each key submission
- `OTP` — needed to decode the final token

### 3.2 Provide Recovery Keys

Since KMS auto-unseal is enabled, you'll use **recovery keys** (not unseal keys):

```bash
# Submit recovery key (repeat for each key until threshold is met)
vault operator generate-root -dr-token \
  -nonce=<nonce_from_step_3.1> \
  <recovery_key>
```

When the threshold is reached, you'll receive an `Encoded Token`.

### 3.3 Decode the DR Operation Token

```bash
vault operator generate-root -dr-token \
  -decode=<encoded_token> \
  -otp=<otp_from_step_3.1>
```

**Save the decoded DR operation token.** You'll need it for the promotion.

### 3.4 Promote the DR Cluster

```bash
export VAULT_ADDR="$(terraform output -json dr_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault write sys/replication/dr/secondary/promote \
  dr_operation_token=<dr_operation_token>
```

**Expected:** DR cluster is promoted to primary. Response shows `mode: primary`.

---

## Step 4 — Verify DR Cluster Is Now Active

```bash
export VAULT_ADDR="$(terraform output -json dr_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

# Check Vault status
vault status

# Login with the same root token
vault login <root_token>

# Verify the test data replicated
vault kv get secret/dr-test
```

**Expected results:**

| Check | Expected |
|-------|----------|
| `vault status` → Sealed | `false` |
| `vault kv get secret/dr-test` → message | `hello-from-primary` |
| Replication mode | `primary` (was `secondary`) |

> **This confirms DR replication is working correctly.** The DR cluster has all data from the primary and is serving requests.

---

## Step 5 — Restore Original Topology (Demote DR Back)

After testing, restore the original primary/secondary relationship.

### 5.1 Demote the Promoted DR Cluster

```bash
export VAULT_ADDR="$(terraform output -json dr_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault login <root_token>
vault write -f sys/replication/dr/primary/demote
```

### 5.2 Re-enable DR on Original Primary

```bash
export VAULT_ADDR="$(terraform output -json primary_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault login <root_token>

# Re-enable as DR primary
vault write -f sys/replication/dr/primary/enable

# Generate a new secondary activation token
vault write -f sys/replication/dr/primary/secondary-token id="dr-secondary"
```

**Save the `wrapping_token` from the output.**

### 5.3 Reconnect DR as Secondary

```bash
export VAULT_ADDR="$(terraform output -json dr_cluster | jq -r '.load_balancer.url')"
export VAULT_SKIP_VERIFY=true

vault write sys/replication/dr/secondary/update-primary \
  dr_operation_token=<dr_operation_token> \
  token=<wrapping_token_from_step_5.2>
```

### 5.4 Verify Restored Topology

```bash
# Check primary
export VAULT_ADDR="$(terraform output -json primary_cluster | jq -r '.load_balancer.url')"
vault read sys/replication/dr/status
# Expected: mode=primary, state=running

# Check DR
export VAULT_ADDR="$(terraform output -json dr_cluster | jq -r '.load_balancer.url')"
vault read sys/replication/dr/status
# Expected: mode=secondary, state=stream-wals
```

---

## Test Summary Checklist

| # | Test | Status |
|---|------|--------|
| 1 | Primary shows `mode=primary`, `state=running` | ☐ |
| 2 | DR shows `mode=secondary`, `state=stream-wals` | ☐ |
| 3 | Test secret written to primary successfully | ☐ |
| 4 | DR operation token generated successfully | ☐ |
| 5 | DR cluster promoted to primary | ☐ |
| 6 | Test secret readable on promoted DR cluster | ☐ |
| 7 | Promoted DR demoted back to secondary | ☐ |
| 8 | Original primary re-enabled and replication restored | ☐ |

---

## Troubleshooting

### DR status shows `state: idle`
Replication is configured but not active. Re-enable on primary:
```bash
vault write -f sys/replication/dr/primary/enable
```

### DR promotion fails with "token invalid"
The DR operation token may have expired. Generate a new one starting from Step 3.1.

### `vault kv get` fails on promoted DR
Wait 30-60 seconds after promotion for WAL replay to complete, then retry.

### Connection refused on NLB endpoint
Vault may still be starting. Check instance logs via SSM:
```bash
aws ssm start-session --target <instance-id>
sudo journalctl -u vault -f
```

### TLS certificate errors
Add `export VAULT_SKIP_VERIFY=true` or use `export VAULT_CACERT=/opt/vault/tls/ca.crt` (on-instance only).

---

## Architecture Reference

```
┌─────────────────────────────┐     VPC Peering     ┌─────────────────────────────┐
│     PRIMARY (us-east-1)     │◄───────────────────►│       DR (us-east-2)        │
│                             │   DR Replication     │                             │
│  NLB ──► Vault Node 0      │   ──────────────►    │  NLB ──► Vault Node 0      │
│          (Raft Leader)      │   WAL Streaming      │          (Raft Leader)      │
│                             │                      │                             │
│  KMS Auto-Unseal            │                      │  KMS Auto-Unseal            │
│  S3 (scripts + TLS + init)  │                      │  S3 (scripts + TLS + init)  │
└─────────────────────────────┘                      └─────────────────────────────┘
```
