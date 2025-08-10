#!/bin/bash

# Mana-Ethereum Monitoring Stack Startup Script
# This script starts the complete monitoring infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$(cd "${SCRIPT_DIR}/../monitoring" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "🚀 Starting Mana-Ethereum Monitoring Stack"
echo "================================================"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ docker-compose is not installed. Please install it and try again."
    exit 1
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p "${MONITORING_DIR}/prometheus/data"
mkdir -p "${MONITORING_DIR}/grafana/data"
mkdir -p "${MONITORING_DIR}/alertmanager/data"

# Set permissions for Grafana
echo "🔧 Setting permissions..."
chmod -R 777 "${MONITORING_DIR}/grafana/data" 2>/dev/null || true

# Start monitoring services
echo "🐳 Starting monitoring services..."
cd "${MONITORING_DIR}"

# Pull latest images
echo "📥 Pulling Docker images..."
docker-compose pull

# Start services
echo "▶️  Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check service health
echo "🔍 Checking service health..."

# Check Prometheus
if curl -s http://localhost:9090/-/healthy >/dev/null; then
    echo "✅ Prometheus is healthy"
else
    echo "⚠️  Prometheus may not be fully ready yet"
fi

# Check Grafana
if curl -s http://localhost:3000/api/health >/dev/null; then
    echo "✅ Grafana is healthy"
else
    echo "⚠️  Grafana may not be fully ready yet"
fi

# Check Alertmanager
if curl -s http://localhost:9093/-/healthy >/dev/null; then
    echo "✅ Alertmanager is healthy"
else
    echo "⚠️  Alertmanager may not be fully ready yet"
fi

echo ""
echo "🎉 Monitoring Stack Started Successfully!"
echo "================================================"
echo ""
echo "📊 Access Points:"
echo "   Grafana:      http://localhost:3000 (admin/mana-ethereum)"
echo "   Prometheus:   http://localhost:9090"
echo "   Alertmanager: http://localhost:9093"
echo ""
echo "📈 Mana-Ethereum Metrics:"
echo "   Metrics URL:  http://localhost:9090/metrics"
echo ""
echo "🛠️  Management Commands:"
echo "   View logs:    docker-compose -f ${MONITORING_DIR}/docker-compose.yml logs -f"
echo "   Stop stack:   docker-compose -f ${MONITORING_DIR}/docker-compose.yml down"
echo "   Restart:      docker-compose -f ${MONITORING_DIR}/docker-compose.yml restart"
echo ""

# Check if Mana-Ethereum is running and metrics are available
echo "🔍 Checking Mana-Ethereum metrics endpoint..."
if curl -s http://localhost:9090/metrics | grep -q "mana_"; then
    echo "✅ Mana-Ethereum metrics are being served!"
    echo "   You can now view dashboards in Grafana"
else
    echo "⚠️  Mana-Ethereum metrics endpoint not detected"
    echo "   Make sure to start the Mana-Ethereum client with monitoring enabled:"
    echo "   cd ${PROJECT_DIR}"
    echo "   mix run --no-halt"
fi

echo ""
echo "📚 For more information, see: ${MONITORING_DIR}/README.md"