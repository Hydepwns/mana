#!/bin/bash

# AntidoteDB Cluster Management Script for Mana-Ethereum
# This script manages the AntidoteDB cluster for distributed storage

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.antidote.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_usage() {
    echo "Usage: $0 {start|stop|restart|status|logs|clean|test}"
    echo ""
    echo "Commands:"
    echo "  start    - Start the AntidoteDB cluster"
    echo "  stop     - Stop the AntidoteDB cluster"
    echo "  restart  - Restart the AntidoteDB cluster"
    echo "  status   - Show cluster status"
    echo "  logs     - Show cluster logs"
    echo "  clean    - Stop cluster and remove all data"
    echo "  test     - Test cluster connectivity"
    exit 1
}

function check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}Error: Docker Compose is not installed${NC}"
        exit 1
    fi
}

function start_cluster() {
    echo -e "${GREEN}Starting AntidoteDB cluster...${NC}"
    docker-compose -f "$COMPOSE_FILE" up -d
    
    echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
    sleep 10
    
    # Check if all nodes are up
    for port in 8087 8088 8089; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health" | grep -q "200"; then
            echo -e "${GREEN}✓ Node on port $port is healthy${NC}"
        else
            echo -e "${RED}✗ Node on port $port is not responding${NC}"
        fi
    done
    
    echo -e "${GREEN}AntidoteDB cluster started successfully${NC}"
}

function stop_cluster() {
    echo -e "${YELLOW}Stopping AntidoteDB cluster...${NC}"
    docker-compose -f "$COMPOSE_FILE" down
    echo -e "${GREEN}AntidoteDB cluster stopped${NC}"
}

function restart_cluster() {
    stop_cluster
    sleep 2
    start_cluster
}

function show_status() {
    echo -e "${GREEN}AntidoteDB Cluster Status:${NC}"
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo -e "\n${GREEN}Node Health:${NC}"
    for port in 8087 8088 8089; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health" | grep -q "200"; then
            echo -e "  ${GREEN}✓${NC} Node on port $port: Healthy"
        else
            echo -e "  ${RED}✗${NC} Node on port $port: Unhealthy"
        fi
    done
}

function show_logs() {
    docker-compose -f "$COMPOSE_FILE" logs -f
}

function clean_cluster() {
    echo -e "${YELLOW}Cleaning AntidoteDB cluster and removing all data...${NC}"
    docker-compose -f "$COMPOSE_FILE" down -v
    echo -e "${GREEN}Cluster cleaned and all data removed${NC}"
}

function test_cluster() {
    echo -e "${GREEN}Testing AntidoteDB cluster connectivity...${NC}"
    
    # Test basic connectivity
    for port in 8087 8088 8089; do
        echo -e "\n${YELLOW}Testing node on port $port...${NC}"
        
        # Check health endpoint
        if curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Health check passed"
        else
            echo -e "  ${RED}✗${NC} Health check failed"
            continue
        fi
        
        # Test with Elixir script if mix is available
        if command -v mix &> /dev/null; then
            cd "$PROJECT_ROOT"
            mix run -e "
                case :gen_tcp.connect('localhost', $port, [:binary, {:packet, 0}], 5000) do
                  {:ok, socket} ->
                    IO.puts('  ✓ TCP connection successful')
                    :gen_tcp.close(socket)
                  {:error, reason} ->
                    IO.puts('  ✗ TCP connection failed: #{inspect(reason)}')
                end
            " 2>/dev/null || echo -e "  ${YELLOW}!${NC} Mix test skipped"
        fi
    done
    
    echo -e "\n${GREEN}Cluster connectivity test complete${NC}"
}

# Main script logic
check_docker

case "$1" in
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    restart)
        restart_cluster
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    clean)
        clean_cluster
        ;;
    test)
        test_cluster
        ;;
    *)
        print_usage
        ;;
esac