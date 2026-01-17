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
echo "  Oracle Linux 9 image pulled"
docker pull fedora:43
echo "  Fedora 43 image pulled"

echo ""
echo "Step 2: Starting containers..."
echo "----------------------------------------"
cd "$PROJECT_DIR"
docker-compose up -d
echo "  Containers started"

echo ""
echo "Step 3: Configuring SSH on Oracle Linux container..."
echo "----------------------------------------"

# Install SSH and configure on Oracle Linux
docker exec oracle-host bash -c "
    set -e
    # Install SSH server, OpenSCAP scanner, and necessary tools
    dnf update -y 2>/dev/null || microdnf update -y 2>/dev/null || yum update -y 2>/dev/null || true
    dnf install -y openssh-server openssh-clients passwd sudo openscap-scanner 2>/dev/null || \
    microdnf install -y openssh-server openssh-clients passwd sudo openscap-scanner 2>/dev/null || \
    yum install -y openssh-server openssh-clients passwd sudo openscap-scanner 2>/dev/null || true

    # Create root password (for demo purposes)
    echo 'root:scap123' | chpasswd 2>/dev/null || echo 'root:scap123' | passwd root --stdin 2>/dev/null || true

    # Configure SSH
    mkdir -p /var/run/sshd
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    ssh-keygen -A 2>/dev/null || true

    # Allow root login and pubkey authentication
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true

    # Find and start sshd
    SSHD_BIN=\"\$(command -v sshd || command -v /usr/sbin/sshd || true)\"
    if [ -z \"\$SSHD_BIN\" ]; then
        echo 'Error: sshd binary not found after installation.'
        exit 1
    fi

    # Kill any existing sshd and start fresh
    pkill sshd 2>/dev/null || true
    sleep 1
    \"\$SSHD_BIN\" -D &
    sleep 2
" || echo "Note: SSH configuration on Oracle Linux may need manual adjustment"

echo "  SSH and OpenSCAP scanner configured on Oracle Linux"

echo ""
echo "Step 4: Configuring Fedora scanner container..."
echo "----------------------------------------"

# Install SSH client, OpenSCAP tools on Fedora
docker exec fedora-scanner bash -c "
    set -e
    # Install OpenSSH client, server, and OpenSCAP tools
    dnf install -y openssh-clients openssh-server openscap-scanner openscap-utils passwd 2>/dev/null || true
    dnf clean all 2>/dev/null || true

    # Create root password (for demo purposes)
    echo 'root:scan123' | chpasswd 2>/dev/null || true

    # Configure SSH server on Fedora
    mkdir -p /var/run/sshd
    ssh-keygen -A 2>/dev/null || true

    # Allow root login
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true

    # Start SSH server on Fedora
    SSHD_BIN=\"\$(command -v sshd || command -v /usr/sbin/sshd || true)\"
    if [ -n \"\$SSHD_BIN\" ]; then
        pkill sshd 2>/dev/null || true
        sleep 1
        \"\$SSHD_BIN\" -D &
        sleep 2
    fi
" || echo "Note: Fedora configuration may need manual adjustment"

echo "  Fedora scanner configured with OpenSCAP tools"

echo ""
echo "Step 5: Setting up passwordless SSH from Fedora to Oracle Linux..."
echo "----------------------------------------"

# Generate SSH key on Fedora (if not exists) and copy to Oracle Linux
docker exec fedora-scanner bash -c "
    set -e
    # Generate SSH key pair without passphrase
    if [ ! -f /root/.ssh/id_rsa ]; then
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' -q
    fi

    # Output the public key
    cat /root/.ssh/id_rsa.pub
" > /tmp/fedora_pubkey.tmp

# Add Fedora's public key to Oracle Linux's authorized_keys
PUBKEY=$(cat /tmp/fedora_pubkey.tmp)
docker exec oracle-host bash -c "
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo '$PUBKEY' >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    # Remove duplicates if any
    sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
"
rm -f /tmp/fedora_pubkey.tmp

# Get Oracle Linux IP address
ORACLE_IP=$(docker inspect -f '{{index .NetworkSettings.Networks "scap-network" "IPAddress"}}' oracle-host 2>/dev/null)
if [ -z "$ORACLE_IP" ] || [ "$ORACLE_IP" = "<no value>" ]; then
    ORACLE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' oracle-host 2>/dev/null | head -n1)
fi

# Add Oracle Linux to Fedora's known_hosts to avoid host key verification prompt
docker exec fedora-scanner bash -c "
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    # Remove old entries and add new host key
    ssh-keyscan -H $ORACLE_IP >> /root/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H oracle-host >> /root/.ssh/known_hosts 2>/dev/null || true
    chmod 600 /root/.ssh/known_hosts
"

echo "  Passwordless SSH configured from Fedora to Oracle Linux"

echo ""
echo "Step 6: Verifying SSH connectivity..."
echo "----------------------------------------"

# Test SSH connection from Fedora to Oracle Linux
if docker exec fedora-scanner ssh -o BatchMode=yes -o ConnectTimeout=5 root@oracle-host "echo 'SSH connection successful'" 2>/dev/null; then
    echo "  SSH connection verified: fedora-scanner -> oracle-host"
else
    echo "  Warning: SSH verification failed. Manual verification may be needed."
    echo "  Try: docker exec fedora-scanner ssh root@oracle-host"
fi

echo ""
echo "Step 7: Waiting for containers to be fully ready..."
echo "----------------------------------------"
sleep 3

# Get container IPs
get_container_ip() {
    local container=$1
    local ip=""
    ip=$(docker inspect -f '{{index .NetworkSettings.Networks "scap-network" "IPAddress"}}' "$container" 2>/dev/null)
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container" 2>/dev/null | head -n1)
    fi
    if [ -z "$ip" ]; then
        ip="unknown"
    fi
    echo "$ip"
}

ORACLE_IP=$(get_container_ip oracle-host)
FEDORA_IP=$(get_container_ip fedora-scanner)

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Container Information:"
echo ""
echo "  Oracle Linux 9 (Target Host):"
echo "    Container: oracle-host"
echo "    IP Address: $ORACLE_IP"
echo "    SSH: root@$ORACLE_IP (password: scap123)"
echo "    OpenSCAP scanner installed (required for oscap-ssh)"
echo ""
echo "  Fedora 43 (Scanner):"
echo "    Container: fedora-scanner"
echo "    IP Address: $FEDORA_IP"
echo "    SSH: root@$FEDORA_IP (password: scan123)"
echo "    OpenSCAP tools installed: oscap, oscap-ssh"
echo ""
echo "Passwordless SSH:"
echo "  From fedora-scanner, you can SSH to oracle-host without a password:"
echo "    docker exec -it fedora-scanner ssh root@oracle-host"
echo ""
echo "  Use oscap-ssh to scan the Oracle Linux host:"
echo "    docker exec -it fedora-scanner oscap-ssh root@oracle-host 22 ..."
echo ""
echo "To view running containers:"
echo "  docker-compose ps"
echo ""
echo "To stop containers:"
echo "  docker-compose down"
echo ""
