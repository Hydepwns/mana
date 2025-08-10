# Mana-Ethereum Monitoring and Observability Stack

This directory contains a comprehensive monitoring and observability solution for the Mana-Ethereum client, featuring Prometheus metrics collection, Grafana dashboards, and AlertManager notifications.

## Overview

The monitoring stack provides:
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization dashboards and alerting
- **AlertManager**: Alert routing and notification management
- **Node Exporter**: System metrics collection

## Quick Start

### 1. Start the Monitoring Stack

```bash
# From the monitoring directory
docker-compose -f docker-compose.monitoring.yml up -d
```

### 2. Configure Mana Client

Ensure your Mana-Ethereum client is configured to expose metrics:

```elixir
# In your config/config.exs or config/prod.exs
config :blockchain, :monitoring,
  enabled: true,
  prometheus: [
    enabled: true,
    collection_interval: 15_000
  ],
  metrics_endpoint: [
    enabled: true,
    port: 9090
  ]
```

### 3. Access the Interfaces

- **Grafana**: http://localhost:3000 (admin/mana-ethereum-admin)
- **Prometheus**: http://localhost:9090
- **AlertManager**: http://localhost:9093

## Dashboards

### 1. Mana-Ethereum Overview
- **File**: `grafana/mana-ethereum-overview.json`
- **Purpose**: High-level client health and performance metrics

### 2. System Metrics
- **File**: `grafana/mana-system-metrics.json`
- **Purpose**: Detailed system resource monitoring

### 3. P2P Network
- **File**: `grafana/mana-p2p-network.json`
- **Purpose**: Network connectivity and peer management

## Metrics Reference

### Core Blockchain Metrics
- `mana_up`: Client status (1 = running, 0 = down)
- `mana_blockchain_height`: Current blockchain height
- `mana_blocks_processed_total`: Total blocks processed
- `mana_block_processing_seconds`: Block processing time histogram
- `mana_sync_progress_ratio`: Sync progress (0.0 to 1.0)

### Transaction Metrics
- `mana_transaction_pool_size`: Current transaction pool size
- `mana_transaction_processing_seconds`: Transaction processing time histogram

### P2P Network Metrics
- `mana_p2p_peers_connected`: Number of connected peers by protocol
- `mana_p2p_messages_total`: Total P2P messages by type and direction

### Storage Metrics
- `mana_storage_operations_total`: Total storage operations by type
- `mana_storage_operation_seconds`: Storage operation latency histogram

### EVM Metrics
- `mana_evm_execution_seconds`: EVM execution time histogram
- `mana_evm_gas_used_total`: Total gas used in EVM executions

### System Metrics
- `mana_memory_usage_bytes`: Memory usage by type (total, processes, atom)
- `mana_disk_usage_bytes`: Disk usage (available, total)
- `mana_disk_usage_ratio`: Disk usage ratio (0.0 to 1.0)
- `mana_erlang_processes`: Number of Erlang processes
- `mana_erlang_schedulers`: Number of Erlang schedulers

## Alert Rules

### Critical Alerts
- **ManaClientDown**: Client is not responding (30s threshold)
- **CriticalMemoryUsage**: Memory usage >4GB (2m threshold)
- **CriticalDiskUsage**: Disk usage >95% (1m threshold)
- **VerySlowBlockProcessing**: Block processing >15s (5m threshold)
- **NoPeersConnected**: No P2P peers connected (5m threshold)

### Warning Alerts
- **HighMemoryUsage**: Memory usage >2GB (5m threshold)
- **HighDiskUsage**: Disk usage >80% (5m threshold)
- **SlowBlockProcessing**: Block processing >5s (10m threshold)
- **LowPeerCount**: <5 peers connected (10m threshold)
- **SyncStalled**: No blockchain height progress (10m threshold)

## Configuration Files

- `prometheus.yml`: Prometheus scrape configuration
- `alertmanager.yml`: Alert routing and notification setup
- `docker-compose.monitoring.yml`: Complete monitoring stack deployment
- `alerts/mana-alerts.yml`: Alert rules for Mana-Ethereum client
- `grafana/`: Dashboard configurations and provisioning