# Mana-Ethereum Production Deployment Guide

## Phase 2.4: Production Readiness & Deployment

This guide provides comprehensive instructions for deploying Mana-Ethereum in production environments with advanced monitoring, security hardening, and performance optimization.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Docker Deployment](#docker-deployment)
4. [Kubernetes Deployment](#kubernetes-deployment)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Security Hardening](#security-hardening)
7. [Performance Tuning](#performance-tuning)
8. [Backup & Recovery](#backup--recovery)
9. [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, CentOS 8+, or RHEL 8+)
- **CPU**: 4+ cores (8+ recommended for production)
- **Memory**: 8GB+ RAM (16GB+ recommended)
- **Storage**: 100GB+ SSD storage
- **Network**: Stable internet connection for blockchain sync

### Software Dependencies

- **Erlang/OTP**: 27.2 or later
- **Elixir**: 1.18 or later
- **Docker**: 20.10+ (for containerized deployment)
- **Kubernetes**: 1.24+ (for orchestrated deployment)
- **AntidoteDB**: 2.4+ (for distributed storage)

### Network Requirements

- **Ports**: 8545 (JSON-RPC), 30303 (P2P), 8087 (AntidoteDB)
- **Firewall**: Configure to allow required ports
- **SSL/TLS**: Valid certificates for secure communication

## Environment Setup

### 1. Production Configuration

Create a production configuration file:

```bash
# Copy production configuration
cp rel/config/prod.exs config/prod.exs

# Set environment variables
export ETHEREUM_NETWORK=mainnet
export ANTIDOTE_HOST=your-antidote-host
export ANTIDOTE_PORT=8087
export DATA_DIR=/var/lib/mana-ethereum
export MONITORING_ENABLED=true
export SSL_ENABLED=true
```

### 2. Environment Variables

Set the following environment variables for production:

```bash
# Database Configuration
export ANTIDOTE_HOST=localhost
export ANTIDOTE_PORT=8087
export ANTIDOTE_POOL_SIZE=50
export ANTIDOTE_TIMEOUT=30000
export ANTIDOTE_RETRY_ATTEMPTS=5
export ANTIDOTE_BATCH_SIZE=1000
export ANTIDOTE_COMPRESSION_ENABLED=true

# Memory Optimization
export MEMORY_CACHE_SIZE=100000
export MEMORY_GC_THRESHOLD=0.8
export MEMORY_COMPRESSION_ENABLED=true
export MEMORY_COMPRESSION_THRESHOLD=1024

# Monitoring Configuration
export MONITORING_ENABLED=true
export METRICS_PORT=9568
export HEALTH_CHECK_PORT=8080
export PROMETHEUS_ENABLED=true
export GRAFANA_ENABLED=true

# Security Configuration
export SSL_ENABLED=true
export SSL_CERT_PATH=/path/to/cert.pem
export SSL_KEY_PATH=/path/to/key.pem
export RATE_LIMITING_ENABLED=true
export MAX_REQUESTS_PER_MINUTE=1000

# Network Configuration
export LISTEN_PORT=8545
export MAX_CONNECTIONS=1000
export CONNECTION_TIMEOUT=30000
export KEEPALIVE_TIMEOUT=60000

# Blockchain Configuration
export ETHEREUM_NETWORK=mainnet
export SYNC_MODE=fast
export MAX_PEERS=50
export BOOTNODES=enode://...
export DATA_DIR=/var/lib/mana-ethereum

# Database Configuration
export DATABASE_TYPE=antidote
export DATABASE_PATH=/var/lib/mana-ethereum/db
export MAX_OPEN_FILES=10000
export CACHE_SIZE=1024
export WRITE_BUFFER_SIZE=64

# Backup Configuration
export BACKUP_ENABLED=true
export BACKUP_SCHEDULE="0 2 * * *"
export BACKUP_RETENTION_DAYS=30
export BACKUP_PATH=/var/backups/mana-ethereum

# Alerting Configuration
export ALERTS_ENABLED=true
export SLACK_WEBHOOK=https://hooks.slack.com/...
export EMAIL_RECIPIENTS=admin@example.com,ops@example.com
export MEMORY_ALERT_THRESHOLD=0.9
export DISK_ALERT_THRESHOLD=0.8
export ERROR_RATE_THRESHOLD=0.05

# Performance Configuration
export WORKER_POOL_SIZE=100
export MAX_CONCURRENT_REQUESTS=1000
export REQUEST_TIMEOUT=30000
export BATCH_SIZE=1000
```

## Docker Deployment

### 1. Dockerfile

Create a production Dockerfile:

```dockerfile
# Use official Elixir image
FROM elixir:1.18-alpine

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    git \
    openssl \
    ca-certificates \
    curl

# Set working directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./
COPY apps/*/mix.exs ./apps/
COPY apps/*/mix.exs ./apps/*/

# Install dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY . .

# Compile application
RUN mix compile --warnings-as-errors

# Create release
RUN mix release

# Create runtime directory
RUN mkdir -p /var/lib/mana-ethereum

# Expose ports
EXPOSE 8545 30303 8087 9568 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run application
CMD ["mix", "run", "--no-halt"]
```

### 2. Docker Compose

Create a `docker-compose.yml` for local testing:

```yaml
version: '3.8'

services:
  mana-ethereum:
    build: .
    container_name: mana-ethereum
    ports:
      - "8545:8545"  # JSON-RPC
      - "30303:30303"  # P2P
      - "9568:9568"  # Metrics
      - "8080:8080"  # Health check
    volumes:
      - mana-data:/var/lib/mana-ethereum
      - ./config:/app/config
    environment:
      - ETHEREUM_NETWORK=mainnet
      - ANTIDOTE_HOST=antidote
      - MONITORING_ENABLED=true
      - SSL_ENABLED=false
    depends_on:
      - antidote
    restart: unless-stopped
    networks:
      - mana-network

  antidote:
    image: antidotedb/antidote:latest
    container_name: antidote
    ports:
      - "8087:8087"
    volumes:
      - antidote-data:/antidote/data
    restart: unless-stopped
    networks:
      - mana-network

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    networks:
      - mana-network

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./monitoring/grafana/datasources:/etc/grafana/provisioning/datasources
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    restart: unless-stopped
    networks:
      - mana-network

volumes:
  mana-data:
  antidote-data:
  prometheus-data:
  grafana-data:

networks:
  mana-network:
    driver: bridge
```

### 3. Docker Deployment Commands

```bash
# Build and start services
docker-compose up -d

# View logs
docker-compose logs -f mana-ethereum

# Scale services
docker-compose up -d --scale mana-ethereum=3

# Stop services
docker-compose down

# Clean up volumes
docker-compose down -v
```

## Kubernetes Deployment

### 1. Namespace

Create a namespace for Mana-Ethereum:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mana-ethereum
  labels:
    name: mana-ethereum
```

### 2. ConfigMap

Create a ConfigMap for configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mana-ethereum-config
  namespace: mana-ethereum
data:
  ETHEREUM_NETWORK: "mainnet"
  ANTIDOTE_HOST: "antidote-service"
  ANTIDOTE_PORT: "8087"
  MONITORING_ENABLED: "true"
  SSL_ENABLED: "true"
  DATA_DIR: "/var/lib/mana-ethereum"
```

### 3. Secret

Create a Secret for sensitive data:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mana-ethereum-secrets
  namespace: mana-ethereum
type: Opaque
data:
  ssl-cert: <base64-encoded-cert>
  ssl-key: <base64-encoded-key>
  slack-webhook: <base64-encoded-webhook>
```

### 4. Deployment

Create a Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mana-ethereum
  namespace: mana-ethereum
spec:
  replicas: 3
  selector:
    matchLabels:
      app: mana-ethereum
  template:
    metadata:
      labels:
        app: mana-ethereum
    spec:
      containers:
      - name: mana-ethereum
        image: mana-ethereum:latest
        ports:
        - containerPort: 8545
          name: json-rpc
        - containerPort: 30303
          name: p2p
        - containerPort: 9568
          name: metrics
        - containerPort: 8080
          name: health
        envFrom:
        - configMapRef:
            name: mana-ethereum-config
        - secretRef:
            name: mana-ethereum-secrets
        volumeMounts:
        - name: mana-data
          mountPath: /var/lib/mana-ethereum
        - name: ssl-certs
          mountPath: /etc/ssl/certs
          readOnly: true
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
          limits:
            memory: "8Gi"
            cpu: "4"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: mana-data
        persistentVolumeClaim:
          claimName: mana-ethereum-pvc
      - name: ssl-certs
        secret:
          secretName: mana-ethereum-secrets
```

### 5. Service

Create a Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mana-ethereum-service
  namespace: mana-ethereum
spec:
  selector:
    app: mana-ethereum
  ports:
  - name: json-rpc
    port: 8545
    targetPort: 8545
  - name: p2p
    port: 30303
    targetPort: 30303
  - name: metrics
    port: 9568
    targetPort: 9568
  - name: health
    port: 8080
    targetPort: 8080
  type: LoadBalancer
```

### 6. Ingress

Create an Ingress for external access:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mana-ethereum-ingress
  namespace: mana-ethereum
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - mana-ethereum.example.com
    secretName: mana-ethereum-tls
  rules:
  - host: mana-ethereum.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: mana-ethereum-service
            port:
              number: 8545
```

## Monitoring & Alerting

### 1. Prometheus Configuration

Create `monitoring/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'mana-ethereum'
    static_configs:
      - targets: ['mana-ethereum:9568']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'antidote'
    static_configs:
      - targets: ['antidote:8087']
    metrics_path: /metrics
    scrape_interval: 30s
```

### 2. Alert Rules

Create `monitoring/alert_rules.yml`:

```yaml
groups:
  - name: mana-ethereum
    rules:
      - alert: HighMemoryUsage
        expr: mana_memory_usage > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% for 5 minutes"

      - alert: HighCPUUsage
        expr: mana_cpu_usage > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for 5 minutes"

      - alert: HighErrorRate
        expr: rate(mana_errors_total[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is above 5% for 2 minutes"

      - alert: ServiceDown
        expr: up{job="mana-ethereum"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Mana-Ethereum service is down"
          description: "Service has been down for more than 1 minute"
```

### 3. Grafana Dashboard

Create dashboard configuration in `monitoring/grafana/dashboards/mana-ethereum.json`:

```json
{
  "dashboard": {
    "title": "Mana-Ethereum Production Dashboard",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "mana_cpu_usage",
            "legendFormat": "CPU Usage %"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "mana_memory_usage",
            "legendFormat": "Memory Usage %"
          }
        ]
      },
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(mana_requests_total[5m])",
            "legendFormat": "Requests/sec"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(mana_errors_total[5m])",
            "legendFormat": "Errors/sec"
          }
        ]
      }
    ]
  }
}
```

## Security Hardening

### 1. SSL/TLS Configuration

Generate SSL certificates:

```bash
# Generate private key
openssl genrsa -out private.key 2048

# Generate certificate signing request
openssl req -new -key private.key -out certificate.csr

# Generate self-signed certificate (for testing)
openssl x509 -req -days 365 -in certificate.csr -signkey private.key -out certificate.crt

# For production, use Let's Encrypt or commercial CA
```

### 2. Firewall Configuration

Configure firewall rules:

```bash
# Allow required ports
sudo ufw allow 8545/tcp  # JSON-RPC
sudo ufw allow 30303/tcp # P2P
sudo ufw allow 30303/udp # P2P
sudo ufw allow 8087/tcp  # AntidoteDB
sudo ufw allow 9568/tcp  # Metrics
sudo ufw allow 8080/tcp  # Health check

# Enable firewall
sudo ufw enable
```

### 3. Security Headers

Configure security headers in your reverse proxy:

```nginx
# Nginx configuration
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline';" always;
```

## Performance Tuning

### 1. System Tuning

Optimize system parameters:

```bash
# Increase file descriptor limits
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Optimize network parameters
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf

# Apply changes
sysctl -p
```

### 2. Erlang VM Tuning

Configure Erlang VM parameters:

```bash
# Set Erlang VM flags
export ERL_FLAGS="+K true +A 64 +W w +P 262144 +Q 65536 +S 16:16 +sbt db +sbwt very_long +swt very_low +MBas ageffcbf +MHas ageffcbf +MMas ageffcbf"
```

### 3. Application Tuning

Configure application parameters:

```elixir
# In config/prod.exs
config :mana, :performance,
  worker_pool_size: 100,
  max_concurrent_requests: 1000,
  request_timeout: 30000,
  batch_size: 1000

config :merkle_patricia_tree, :memory_optimizer,
  max_cache_size: 100000,
  gc_threshold: 0.8,
  compression_enabled: true
```

## Backup & Recovery

### 1. Backup Strategy

Create backup scripts:

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/var/backups/mana-ethereum"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="mana-ethereum-backup-$DATE.tar.gz"

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup data directory
tar -czf $BACKUP_DIR/$BACKUP_FILE /var/lib/mana-ethereum

# Backup configuration
cp /etc/mana-ethereum/config.exs $BACKUP_DIR/config-$DATE.exs

# Cleanup old backups (keep last 30 days)
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete
find $BACKUP_DIR -name "config-*.exs" -mtime +30 -delete

echo "Backup completed: $BACKUP_FILE"
```

### 2. Recovery Procedure

Create recovery script:

```bash
#!/bin/bash
# recovery.sh

BACKUP_FILE=$1
DATA_DIR="/var/lib/mana-ethereum"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file>"
    exit 1
fi

# Stop services
systemctl stop mana-ethereum

# Restore data
tar -xzf $BACKUP_FILE -C /

# Restore configuration
cp config-*.exs /etc/mana-ethereum/config.exs

# Start services
systemctl start mana-ethereum

echo "Recovery completed"
```

### 3. Automated Backups

Set up cron job for automated backups:

```bash
# Add to crontab
0 2 * * * /path/to/backup.sh >> /var/log/mana-ethereum-backup.log 2>&1
```

## Troubleshooting

### 1. Common Issues

#### High Memory Usage

```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head -10

# Check Erlang memory
erl -eval "io:format(\"~p~n\", [erlang:memory()])" -s erlang halt
```

#### High CPU Usage

```bash
# Check CPU usage
top
htop

# Check Erlang processes
erl -eval "io:format(\"~p~n\", [length(erlang:processes())])" -s erlang halt
```

#### Network Issues

```bash
# Check network connectivity
netstat -tulpn | grep :8545
ss -tulpn | grep :8545

# Check firewall
sudo ufw status
```

### 2. Log Analysis

```bash
# View application logs
tail -f /var/log/mana-ethereum/application.log

# View system logs
journalctl -u mana-ethereum -f

# Search for errors
grep -i error /var/log/mana-ethereum/*.log
```

### 3. Performance Monitoring

```bash
# Check metrics endpoint
curl http://localhost:9568/metrics

# Check health endpoint
curl http://localhost:8080/health

# Monitor in real-time
watch -n 1 'curl -s http://localhost:9568/metrics | grep mana_'
```

### 4. Emergency Procedures

#### Service Restart

```bash
# Graceful restart
systemctl restart mana-ethereum

# Force restart if needed
systemctl stop mana-ethereum
pkill -f mana-ethereum
systemctl start mana-ethereum
```

#### Data Recovery

```bash
# Stop service
systemctl stop mana-ethereum

# Restore from backup
/path/to/recovery.sh /path/to/backup-file

# Verify data integrity
mix mana.verify_data
```

## Support

For additional support and troubleshooting:

1. **Documentation**: Check the project documentation
2. **Issues**: Report issues on GitHub
3. **Community**: Join the community discussions
4. **Monitoring**: Use the monitoring dashboard for real-time insights

---

**Phase 2.4 Status**: ✅ **COMPLETE**  
**Next Phase**: 🚧 **Phase 3: Advanced Blockchain Features** (Ready to Begin)
