#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================="
echo "SCAP Automation Project Setup"
echo "========================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose > /dev/null 2>&1 && ! docker compose version > /dev/null 2>&1; then
    echo "Error: docker-compose is not installed. Please install docker-compose and try again."
    exit 1
fi

echo "Step 1: Pulling required Docker images..."
echo "----------------------------------------"
docker pull oraclelinux:9
echo "✓ Oracle Linux image pulled"

echo ""
echo "Step 2: Starting container..."
echo "----------------------------------------"
cd "$PROJECT_DIR"
docker-compose up -d
echo "✓ Container started"

echo ""
echo "Step 3: Configuring SSH on Oracle Linux container..."
echo "----------------------------------------"
echo "Installing SSH server and configuring..."

# Install SSH and configure
docker exec oracle-host bash -c "
    set -e
    # Install SSH server and necessary tools
    dnf update -y 2>/dev/null || microdnf update -y 2>/dev/null || yum update -y 2>/dev/null || true
    dnf install -y openssh-server openssh-clients passwd sudo 2>/dev/null || \
    microdnf install -y openssh-server openssh-clients passwd sudo 2>/dev/null || \
    yum install -y openssh-server openssh-clients passwd sudo 2>/dev/null || true
    
    # Create root password (for demo purposes - in production use proper key-based auth)
    echo 'root:scap123' | chpasswd 2>/dev/null || echo 'root:scap123' | passwd root --stdin 2>/dev/null || true
    
    # Configure SSH
    mkdir -p /var/run/sshd
    ssh-keygen -A 2>/dev/null || true
    
    # Allow root login (demo only - adjust for production)
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || \
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
    
    # Find sshd binary
    SSHD_BIN=\"\$(command -v sshd || command -v /usr/sbin/sshd || true)\"
    if [ -z \"\$SSHD_BIN\" ]; then
        echo 'Error: sshd binary not found after installation. Please check package install.'
        exit 1
    fi
    
    # Start SSH service
    \"\$SSHD_BIN\" -D &
    sleep 2
" || echo "Note: SSH configuration may need manual adjustment (sshd may not have started)"

echo "✓ SSH configured"

echo ""
echo "Step 4: Waiting for container to be ready..."
echo "----------------------------------------"
sleep 5

# Get container IP (scap-network only)
get_oracle_ip() {
    local ip=""
    ip=$(docker inspect -f '{{index .NetworkSettings.Networks "scap-network" | index "IPAddress"}}' oracle-host 2>/dev/null)
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        ip=$(docker network inspect scap-network --format '{{range .Containers}}{{if eq .Name "oracle-host"}}{{.IPv4Address}}{{end}}{{end}}' 2>/dev/null | cut -d'/' -f1)
    fi
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' oracle-host 2>/dev/null | head -n1)
    fi
    if [ -z "$ip" ]; then
        ip="unknown"
    fi
    echo "$ip"
}

ORACLE_IP=$(get_oracle_ip)

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Container Information:"
echo "  Oracle Linux Host:"
echo "    Container: oracle-host"
echo "    IP Address: $ORACLE_IP"
echo "    SSH: root@$ORACLE_IP (password: scap123)"
echo ""
echo "To view running containers:"
echo "  docker-compose ps"
echo ""
echo "To stop containers:"
echo "  docker-compose down"
echo ""
