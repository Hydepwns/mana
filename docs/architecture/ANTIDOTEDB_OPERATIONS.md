# AntidoteDB Operational Procedures

## Table of Contents
1. [Overview](#overview)
2. [Installation & Setup](#installation--setup)
3. [Cluster Management](#cluster-management)
4. [Backup & Recovery](#backup--recovery)
5. [Monitoring & Health Checks](#monitoring--health-checks)
6. [Performance Tuning](#performance-tuning)
7. [Troubleshooting](#troubleshooting)
8. [Security](#security)

## Overview

AntidoteDB is a distributed CRDT database that provides Mana-Ethereum with:
- **Distributed storage** across multiple nodes
- **Eventual consistency** with CRDT conflict resolution
- **Partition tolerance** for network splits
- **Multi-datacenter** operation capabilities

### Key Components

- **AntidoteDB Cluster**: 3+ nodes for fault tolerance
- **Connection Pool**: Manages client connections with circuit breakers
- **Backup Manager**: Automated backups and snapshots
- **CRDT Types**: Custom implementations for blockchain data

## Installation & Setup

### Prerequisites

- Docker and Docker Compose
- Elixir 1.18+ with Erlang/OTP 26+
- At least 8GB RAM per node
- 100GB+ disk space for blockchain data

### Initial Setup

1. **Start AntidoteDB Cluster**:
```bash
# Start 3-node cluster
docker-compose -f docker-compose.antidote.yml up -d

# Verify cluster status
./scripts/antidote_cluster.sh status
```

2. **Initialize Cluster**:
```bash
# Form cluster (first time only)
./scripts/antidote_cluster.sh init

# Join nodes to cluster
./scripts/antidote_cluster.sh join
```

3. **Configure Mana**:
```elixir
# config/config.exs
config :merkle_patricia_tree,
  db_backend: MerklePatriciaTree.DB.Antidote,
  antidote_nodes: [
    {127, 0, 0, 1, 8087},
    {127, 0, 0, 1, 8088},
    {127, 0, 0, 1, 8089}
  ]
```

## Cluster Management

### Starting the Cluster

```bash
# Start all nodes
docker-compose -f docker-compose.antidote.yml up -d

# Start specific node
docker-compose -f docker-compose.antidote.yml up -d mana_antidote1
```

### Stopping the Cluster

```bash
# Graceful shutdown
docker-compose -f docker-compose.antidote.yml stop

# Force stop (not recommended)
docker-compose -f docker-compose.antidote.yml kill
```

### Scaling the Cluster

1. **Add New Node**:
```yaml
# Add to docker-compose.antidote.yml
mana_antidote4:
  image: antidotedb/antidote:latest
  ports:
    - "8090:8087"
  environment:
    - NODE_NAME=antidote4@antidote4
  volumes:
    - antidote4_data:/antidote-data
```

2. **Join to Cluster**:
```bash
./scripts/antidote_cluster.sh add-node antidote4
```

3. **Rebalance Data**:
```bash
# Data automatically rebalances via CRDT replication
# Monitor progress:
./scripts/antidote_cluster.sh rebalance-status
```

### Removing Nodes

```bash
# Gracefully remove node
./scripts/antidote_cluster.sh remove-node antidote3

# Wait for data migration
./scripts/antidote_cluster.sh migration-status
```

## Backup & Recovery

### Automatic Backups

Backups run automatically every hour by default:

```elixir
# Start backup manager with custom settings
{:ok, _} = MerklePatriciaTree.DB.BackupManager.start_link(
  backup_interval_ms: 3_600_000,  # 1 hour
  backup_dir: "/var/backups/antidote",
  max_backups: 24  # Keep last 24 hours
)
```

### Manual Backup Operations

```bash
# Create immediate backup
mix antidote_backup backup --description "Before upgrade"

# Create named snapshot
mix antidote_backup snapshot --name "v1.0-release" --description "Production release"

# List available backups
mix antidote_backup list

# Show backup statistics
mix antidote_backup stats
```

### Recovery Procedures

#### Full Restore

```bash
# List backups to find ID
mix antidote_backup list

# Restore from specific backup
mix antidote_backup restore --id backup_1234567890_1234

# Force restore without confirmation
mix antidote_backup restore --id snapshot_v1.0-release --force
```

#### Partial Recovery

For corrupted nodes, restore single node:

```bash
# Stop corrupted node
docker-compose -f docker-compose.antidote.yml stop mana_antidote2

# Clear node data
docker volume rm mana_antidote2_data

# Restart node (will sync from cluster)
docker-compose -f docker-compose.antidote.yml up -d mana_antidote2
```

### Backup Retention

```bash
# Clean up old backups (keep last 10)
mix antidote_backup cleanup --keep 10

# Automated cleanup (in BackupManager config)
max_backups: 24  # Automatically removes older backups
```

## Monitoring & Health Checks

### Health Check Endpoints

```bash
# Check node health
curl http://localhost:8087/health

# Check cluster status
curl http://localhost:8087/cluster/status

# Check replication lag
curl http://localhost:8087/replication/lag
```

### Prometheus Metrics

AntidoteDB exports metrics on port 9090:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'antidote'
    static_configs:
      - targets: ['localhost:8087', 'localhost:8088', 'localhost:8089']
```

Key metrics to monitor:
- `antidote_operations_total` - Total operations
- `antidote_latency_microseconds` - Operation latency
- `antidote_replication_lag_ms` - Replication delay
- `antidote_crdt_conflicts_total` - CRDT conflict resolutions

### Grafana Dashboard

Import the dashboard from `monitoring/antidote-dashboard.json`:

1. Open Grafana (http://localhost:3000)
2. Import dashboard
3. Select Prometheus datasource
4. View real-time metrics

### Alert Rules

```yaml
# alerts.yml
groups:
  - name: antidote
    rules:
      - alert: HighReplicationLag
        expr: antidote_replication_lag_ms > 5000
        for: 5m
        annotations:
          summary: "High replication lag on {{ $labels.node }}"

      - alert: NodeDown
        expr: up{job="antidote"} == 0
        for: 1m
        annotations:
          summary: "AntidoteDB node {{ $labels.instance }} is down"
```

## Performance Tuning

### Connection Pool Settings

```elixir
# Optimize for your workload
config :merkle_patricia_tree,
  connection_pool: [
    size: 100,                    # Number of connections
    max_overflow: 50,             # Additional connections under load
    strategy: :fifo,              # Connection allocation strategy
    checkout_timeout: 5_000       # Max wait for connection (ms)
  ]
```

### CRDT Optimization

```elixir
# Configure CRDT parameters
config :merkle_patricia_tree,
  crdt_settings: [
    merge_interval: 100,          # Merge CRDTs every N operations
    gc_interval: 3_600_000,       # Garbage collect every hour
    compression: true,            # Enable value compression
    batch_size: 1000             # Batch operation size
  ]
```

### Memory Management

```elixir
# Memory optimizer settings
config :merkle_patricia_tree,
  memory_optimizer: [
    cache_size: 10_000,          # Max cached entries
    gc_threshold: 0.8,           # Trigger GC at 80% memory
    compact_interval: 300_000     # Compact cache every 5 minutes
  ]
```

### Network Optimization

```yaml
# docker-compose.antidote.yml
services:
  mana_antidote1:
    environment:
      - ANTIDOTE_TXN_CERT=false  # Disable if not needed
      - ANTIDOTE_RECOVER_FROM_LOG=true
      - ANTIDOTE_META_DATA_ON_START=false
      - ANTIDOTE_SYNC_LOG=false  # Disable for performance
```

## Troubleshooting

### Common Issues

#### 1. Connection Refused

**Symptom**: Cannot connect to AntidoteDB

**Solution**:
```bash
# Check if containers are running
docker ps | grep antidote

# Check logs
docker logs mana_antidote1 --tail 50

# Restart containers
docker-compose -f docker-compose.antidote.yml restart
```

#### 2. High Replication Lag

**Symptom**: Data not syncing between nodes

**Solution**:
```bash
# Check network connectivity
docker exec mana_antidote1 ping antidote2

# Check replication status
curl http://localhost:8087/replication/status

# Force sync
./scripts/antidote_cluster.sh force-sync
```

#### 3. Memory Issues

**Symptom**: OOM errors or high memory usage

**Solution**:
```elixir
# Trigger manual GC
:erlang.garbage_collect()

# Reduce cache size
MerklePatriciaTree.DB.MemoryOptimizer.set_cache_size(5000)

# Enable aggressive GC
System.flag(:fullsweep_after, 10)
```

#### 4. Disk Space Issues

**Symptom**: Disk full errors

**Solution**:
```bash
# Check disk usage
docker exec mana_antidote1 df -h

# Clean up old backups
mix antidote_backup cleanup --keep 5

# Compact database
docker exec mana_antidote1 antidote-admin compact
```

### Debug Commands

```bash
# Enable debug logging
docker exec mana_antidote1 antidote-admin set-log-level debug

# Dump cluster state
docker exec mana_antidote1 antidote-admin dump-state > cluster_state.txt

# Check CRDT conflicts
docker exec mana_antidote1 antidote-admin show-conflicts

# Force garbage collection
docker exec mana_antidote1 antidote-admin gc
```

## Security

### Network Security

1. **Firewall Rules**:
```bash
# Allow only internal traffic
iptables -A INPUT -p tcp --dport 8087 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 8087 -j DROP
```

2. **TLS Configuration**:
```yaml
# Enable TLS in docker-compose
environment:
  - ANTIDOTE_TLS_ENABLED=true
  - ANTIDOTE_CERT_FILE=/certs/antidote.crt
  - ANTIDOTE_KEY_FILE=/certs/antidote.key
```

### Access Control

```elixir
# Configure authentication
config :merkle_patricia_tree,
  antidote_auth: [
    enabled: true,
    username: System.get_env("ANTIDOTE_USER"),
    password: System.get_env("ANTIDOTE_PASS")
  ]
```

### Encryption at Rest

```yaml
# Enable encryption
environment:
  - ANTIDOTE_ENCRYPTION=true
  - ANTIDOTE_ENCRYPTION_KEY_FILE=/keys/master.key
```

### Audit Logging

```elixir
# Enable audit logs
config :merkle_patricia_tree,
  audit_log: [
    enabled: true,
    path: "/var/log/antidote/audit.log",
    rotation: :daily,
    keep: 30
  ]
```

## Maintenance Windows

### Planned Maintenance

1. **Announce maintenance**:
```bash
# Send notification to monitoring
curl -X POST http://monitoring/maintenance/start
```

2. **Backup data**:
```bash
mix antidote_backup backup --description "Pre-maintenance backup"
```

3. **Perform maintenance**:
```bash
# Update one node at a time
docker-compose -f docker-compose.antidote.yml stop mana_antidote1
# ... perform updates ...
docker-compose -f docker-compose.antidote.yml up -d mana_antidote1
# Wait for sync
./scripts/antidote_cluster.sh wait-sync antidote1
```

4. **Verify cluster**:
```bash
./scripts/antidote_cluster.sh verify
```

### Emergency Procedures

#### Data Corruption

1. Stop affected node immediately
2. Restore from latest backup
3. Resync with cluster
4. Verify data integrity

#### Split Brain

1. Identify partition
2. Stop minority partition
3. Force rejoin to majority
4. Verify consistency

#### Complete Cluster Failure

1. Stop all nodes
2. Restore from latest snapshot
3. Start primary node
4. Join secondary nodes
5. Verify full restoration

## Performance Benchmarks

Expected performance with 3-node cluster:

| Operation | Single Op | Batch (1000) | Concurrent (100 clients) |
|-----------|-----------|--------------|-------------------------|
| Read      | < 1ms     | < 10ms       | 300K ops/sec           |
| Write     | < 2ms     | < 20ms       | 150K ops/sec           |
| CAS       | < 3ms     | < 30ms       | 100K ops/sec           |

## Support & Resources

- **Documentation**: [AntidoteDB Docs](https://antidotedb.eu/docs/)
- **GitHub Issues**: [axol-io/issues](https://github.com/axol-io/mana/issues)
- **Community Chat**: Discord/Telegram
- **Emergency Support**: hello@axol-io.org

## Appendix: Scripts

### Health Check Script

```bash
#!/bin/bash
# check_antidote_health.sh

NODES=("localhost:8087" "localhost:8088" "localhost:8089")

for node in "${NODES[@]}"; do
  if curl -f -s "http://$node/health" > /dev/null; then
    echo "✅ $node is healthy"
  else
    echo "❌ $node is unhealthy"
    exit 1
  fi
done
```

### Backup Verification Script

```bash
#!/bin/bash
# verify_backup.sh

BACKUP_ID=$1
TEMP_DIR="/tmp/backup_verify_$$"

# Create test environment
mkdir -p $TEMP_DIR

# Attempt restore to test environment
mix antidote_backup restore --id $BACKUP_ID --target $TEMP_DIR

# Verify data integrity
if antidote-admin verify --data-dir $TEMP_DIR; then
  echo "✅ Backup $BACKUP_ID is valid"
  rm -rf $TEMP_DIR
  exit 0
else
  echo "❌ Backup $BACKUP_ID is corrupted"
  rm -rf $TEMP_DIR
  exit 1
fi
```
