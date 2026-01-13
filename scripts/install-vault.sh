#!/bin/bash
set -euo pipefail

# Script parameters
NODE_ID="${1:-1}"
CLUSTER_PEERS="${2:-}"
VAULT_VERSION="${3:-1.15.4}"

# Derived variables
NODE_NAME="vault-node-${NODE_ID}"
VAULT_USER="vault"
VAULT_GROUP="vault"
VAULT_DIR="/opt/vault"
VAULT_DATA_DIR="${VAULT_DIR}/data"
VAULT_CONFIG_DIR="/etc/vault.d"
VAULT_LOG_DIR="/var/log/vault"

# Get the current node's IP address
NODE_IP=$(hostname -I | awk '{print $1}')

echo "=== Installing HashiCorp Vault ${VAULT_VERSION} on ${NODE_NAME} ==="
echo "Node IP: ${NODE_IP}"
echo "Cluster Peers: ${CLUSTER_PEERS}"

# Update system and install dependencies
echo "=== Installing dependencies ==="
apt-get update
apt-get install -y unzip jq curl

# Create vault user and group
echo "=== Creating vault user and group ==="
if ! getent group ${VAULT_GROUP} > /dev/null 2>&1; then
    groupadd --system ${VAULT_GROUP}
fi

if ! getent passwd ${VAULT_USER} > /dev/null 2>&1; then
    useradd --system --gid ${VAULT_GROUP} --home ${VAULT_DIR} --shell /bin/false ${VAULT_USER}
fi

# Create directories
echo "=== Creating directories ==="
mkdir -p ${VAULT_DIR}
mkdir -p ${VAULT_DATA_DIR}
mkdir -p ${VAULT_CONFIG_DIR}
mkdir -p ${VAULT_LOG_DIR}

# Download and install Vault
echo "=== Downloading Vault ${VAULT_VERSION} ==="
cd /tmp
curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o vault.zip
unzip -o vault.zip
mv vault /usr/local/bin/
chmod +x /usr/local/bin/vault
rm vault.zip

# Verify installation
vault version

# Build retry_join configuration
RETRY_JOIN_CONFIG=""
IFS=',' read -ra PEER_IPS <<< "${CLUSTER_PEERS}"
for peer_ip in "${PEER_IPS[@]}"; do
    RETRY_JOIN_CONFIG="${RETRY_JOIN_CONFIG}
  retry_join {
    leader_api_addr = \"http://${peer_ip}:8200\"
  }"
done

# Create Vault configuration (TLS disabled for learning)
echo "=== Creating Vault configuration ==="
cat > ${VAULT_CONFIG_DIR}/vault.hcl << EOF
# Vault configuration for ${NODE_NAME}
# TLS disabled for learning environment

ui = true
disable_mlock = true

# Cluster information
cluster_name = "vault-learn-cluster"
cluster_addr = "http://${NODE_IP}:8201"
api_addr     = "http://${NODE_IP}:8200"

# Listener configuration - TLS disabled
listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

# Raft storage configuration
storage "raft" {
  path    = "${VAULT_DATA_DIR}"
  node_id = "${NODE_NAME}"
${RETRY_JOIN_CONFIG}
}
EOF

# Set ownership
chown -R ${VAULT_USER}:${VAULT_GROUP} ${VAULT_DIR}
chown -R ${VAULT_USER}:${VAULT_GROUP} ${VAULT_CONFIG_DIR}
chown -R ${VAULT_USER}:${VAULT_GROUP} ${VAULT_LOG_DIR}

# Create systemd service
echo "=== Creating systemd service ==="
cat > /etc/systemd/system/vault.service << EOF
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=${VAULT_CONFIG_DIR}/vault.hcl

[Service]
User=${VAULT_USER}
Group=${VAULT_GROUP}
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=${VAULT_CONFIG_DIR}/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Vault service
echo "=== Enabling and starting Vault service ==="
systemctl daemon-reload
systemctl enable vault
systemctl start vault

# Wait for Vault to start
echo "=== Waiting for Vault to start ==="
sleep 5

# Check Vault status
echo "=== Vault installation complete ==="
export VAULT_ADDR="http://127.0.0.1:8200"
vault status || true

echo "=== Installation script completed for ${NODE_NAME} ==="
echo ""
echo "Next steps:"
echo "1. Set environment: export VAULT_ADDR='http://127.0.0.1:8200'"
echo "2. Initialize Vault on node 1: vault operator init"
echo "3. Unseal Vault on all nodes: vault operator unseal"
echo "4. Other nodes will auto-join via Raft"
