# Vault DR Lab - Scripts Guide

Quick reference for all operational and monitoring scripts.

## 📁 Script Organization

```
scripts/
├── deploy-to-fyre.sh              # Main deployment (in root)
├── install-vault.sh               # Vault installation
├── configure-haproxy.sh           # HAProxy setup
├── operations/                    # Operational scripts
│   ├── upgrade-vault.sh          # Version upgrades
│   └── check-cluster-health.sh   # Health checks
└── monitoring/                    # Performance monitoring
    ├── check-performance.sh      # System performance
    └── performance-test.sh       # Load testing
```

## 🚀 Deployment Scripts

### deploy-to-fyre.sh
**Purpose**: Main deployment automation  
**Location**: `./deploy-to-fyre.sh`

```bash
# Full deployment
./deploy-to-fyre.sh
# Select option 6 (Full Deployment)
```

## 🔧 Operations Scripts

### 1. Upgrade Vault Version
**Script**: `scripts/operations/upgrade-vault.sh`  
**Purpose**: Rolling upgrade of Vault nodes

```bash
# Upgrade primary cluster
./scripts/operations/upgrade-vault.sh 1.22.0+ent primary

# Upgrade DR cluster
./scripts/operations/upgrade-vault.sh 1.22.0+ent dr

# Upgrade both clusters
./scripts/operations/upgrade-vault.sh 1.22.0+ent both
```

**What it does:**
- Downloads new Vault version
- Stops Vault service
- Installs new binary
- Restarts service
- Verifies upgrade
- Upgrades one node at a time (rolling upgrade)

### 2. Check Cluster Health
**Script**: `scripts/operations/check-cluster-health.sh`  
**Purpose**: Comprehensive health check of all nodes

```bash
./scripts/operations/check-cluster-health.sh
```

**Checks:**
- SSH connectivity to all nodes
- Vault service status
- Vault initialization status
- Sealed/unsealed status
- Vault version
- HAProxy status
- Cluster accessibility via load balancers

## 📊 Monitoring Scripts

### 1. Check Performance
**Script**: `scripts/monitoring/check-performance.sh`  
**Purpose**: Monitor system resources and identify bottlenecks

```bash
./scripts/monitoring/check-performance.sh
```

**Monitors:**
- CPU usage per node
- Memory usage per node
- Disk usage
- Vault process stats
- Network connections
- Recent errors in logs
- System load
- HAProxy backend health
- Vault metrics

**Bottleneck Indicators:**
- High CPU (>80%) - Need more CPU or optimization
- High memory (>90%) - Need more RAM
- High disk usage - Need more storage
- Many connections - May indicate issues
- Errors in logs - Investigate immediately

### 2. Performance Load Test
**Script**: `scripts/monitoring/performance-test.sh`  
**Purpose**: Run load tests to measure Vault performance

```bash
# Requires Vault address and token
./scripts/monitoring/performance-test.sh https://10.16.23.48:8200 s.xxxxx
```

**Tests:**
1. **Write Performance**: 100 KV writes
2. **Read Performance**: 100 KV reads
3. **List Performance**: 50 list operations
4. **Token Creation**: 50 token creations
5. **Concurrent Operations**: 20 parallel writes
6. **Large Data**: 10 writes of 10KB each

**Interpreting Results:**
- Write < 10/sec → Disk I/O bottleneck
- Read < 50/sec → CPU/network bottleneck
- Concurrent slow → Resource contention
- Large data slow → Network/disk bandwidth

## 📋 Common Workflows

### Daily Health Check
```bash
# Check cluster health
./scripts/operations/check-cluster-health.sh

# Check performance
./scripts/monitoring/check-performance.sh
```

### Performance Investigation
```bash
# 1. Check current performance
./scripts/monitoring/check-performance.sh

# 2. Run load test
./scripts/monitoring/performance-test.sh https://<LB_IP>:8200 <token>

# 3. Analyze results and identify bottlenecks
```

### Version Upgrade
```bash
# 1. Check current health
./scripts/operations/check-cluster-health.sh

# 2. Upgrade DR cluster first (test)
./scripts/operations/upgrade-vault.sh 1.22.0+ent dr

# 3. Verify DR cluster
./scripts/operations/check-cluster-health.sh

# 4. Upgrade primary cluster
./scripts/operations/upgrade-vault.sh 1.22.0+ent primary

# 5. Final verification
./scripts/operations/check-cluster-health.sh
```

## 🔍 Troubleshooting with Scripts

### Issue: Vault Performance Degraded
```bash
# 1. Check system resources
./scripts/monitoring/check-performance.sh

# 2. Look for:
#    - High CPU/memory usage
#    - Disk I/O issues
#    - Network connection spikes
#    - Errors in logs

# 3. Run performance test
./scripts/monitoring/performance-test.sh https://<LB_IP>:8200 <token>

# 4. Compare with baseline metrics
```

### Issue: Node Not Responding
```bash
# 1. Check cluster health
./scripts/operations/check-cluster-health.sh

# 2. SSH to problematic node
ssh -i ~/.ssh/fyre_key.pem ubuntu@<node_ip>

# 3. Check Vault logs
sudo journalctl -u vault -f

# 4. Check system resources
top
df -h
```

### Issue: After Upgrade Problems
```bash
# 1. Check all nodes are upgraded
./scripts/operations/check-cluster-health.sh

# 2. Check for version mismatches
# All nodes should show same version

# 3. Check Vault logs for errors
ssh <node_ip> "sudo journalctl -u vault --since '10 minutes ago'"
```

## 📝 Script Requirements

All scripts require:
- `inventory.txt` configured with VM IPs
- SSH access to all VMs
- `jq` installed on local machine (for JSON parsing)
- Vault CLI installed locally (for performance tests)

## 🎯 Best Practices

1. **Always check health before operations**
   ```bash
   ./scripts/operations/check-cluster-health.sh
   ```

2. **Run performance checks regularly**
   ```bash
   # Daily or weekly
   ./scripts/monitoring/check-performance.sh > performance-$(date +%Y%m%d).log
   ```

3. **Test upgrades on DR first**
   ```bash
   ./scripts/operations/upgrade-vault.sh <version> dr
   # Verify before upgrading primary
   ```

4. **Keep performance baselines**
   ```bash
   # Run after initial deployment
   ./scripts/monitoring/performance-test.sh <addr> <token> > baseline.log
   # Compare future tests against this
   ```

5. **Monitor during high load**
   ```bash
   # Run in background during load tests
   watch -n 5 './scripts/monitoring/check-performance.sh'
   ```

## 🆘 Quick Reference

| Task | Command |
|------|---------|
| Deploy lab | `./deploy-to-fyre.sh` |
| Check health | `./scripts/operations/check-cluster-health.sh` |
| Check performance | `./scripts/monitoring/check-performance.sh` |
| Run load test | `./scripts/monitoring/performance-test.sh <addr> <token>` |
| Upgrade Vault | `./scripts/operations/upgrade-vault.sh <version> <cluster>` |

---

**Note**: All scripts use the `inventory.txt` file for VM IP addresses. Ensure it's configured before running any scripts.