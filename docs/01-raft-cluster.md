# Raft Integrated Storage Cluster Setup

This guide covers setting up and managing a 3-node HashiCorp Vault cluster using Raft integrated storage for high availability.

## Overview

### What is Raft?

Raft is a consensus algorithm that Vault uses for:
- **Leader Election**: Automatically elects a leader node to handle all write operations
- **Log Replication**: Replicates data across all cluster nodes
- **Consistency**: Ensures all nodes have the same data state

### Cluster Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Vault Raft Cluster                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ vault-node-1│    │ vault-node-2│    │ vault-node-3│     │
│  │   (Leader)  │◄──►│  (Follower) │◄──►│  (Follower) │     │
│  │ 10.0.1.11   │    │ 10.0.1.12   │    │ 10.0.1.13   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                     Port 8201 (Raft)                        │
│                     Port 8200 (API)                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key Concepts

| Term | Description |
|------|-------------|
| **Leader** | The node that handles all write operations and replicates to followers |
| **Follower** | Nodes that replicate data from the leader and can serve read requests |
| **Quorum** | Majority of nodes required for cluster operations (2 of 3 nodes) |
| **Term** | A logical clock that increments with each leader election |

## Prerequisites

Before starting, ensure:
- [ ] All 3 VMs are deployed and running
- [ ] Vault is installed on all nodes (via Custom Script Extension)
- [ ] Network connectivity on ports 8200 and 8201 between nodes
- [ ] TLS certificates are configured
- [ ] Azure CLI installed and authenticated (`az login`)

## Connecting to the VMs

### Retrieve SSH Private Key from Azure Key Vault

The SSH private key for VM access is stored in Azure Key Vault. Follow these steps to download it and connect to the VMs.

#### 1. Download the Private Key

```bash
# Retrieve the private key from Azure Key Vault and save to ~/.ssh/
az keyvault secret show \
  --vault-name kv-vault-learn \
  --name vault-vm-ssh-private-key \
  --query value \
  -o tsv > ~/.ssh/vault-vm-key.pem
```

#### 2. Set Correct Permissions

SSH requires strict permissions on private key files:

```bash
# Set read-only permission for owner only
chmod 600 ~/.ssh/vault-vm-key.pem
```

#### 3. Connect to the VMs

Connect to each Vault node using the private key:

```bash
# Connect to vault-node-1
ssh -i ~/.ssh/vault-vm-key.pem vaultadmin@PUBLIC-IP

# Connect to vault-node-2
ssh -i ~/.ssh/vault-vm-key.pem vaultadmin@PUBLIC-IP

# Connect to vault-node-3
ssh -i ~/.ssh/vault-vm-key.pem vaultadmin@PUBLIC-IP
```


## Step 1: Verify Vault Installation

SSH into each node and verify Vault is running:

```bash
# Set environment variables
export VAULT_ADDR="http://127.0.0.1:8200"

# Check Vault status
vault status
```

Expected output (before initialization):
```
Key                      Value
---                      -----
Seal Type                shamir
Initialized              false
Sealed                   true
Total Shares             0
Threshold                0
Unseal Progress          0/0
Unseal Nonce             n/a
Version                  1.15.4
Build Date               2023-12-04T17:45:28Z
Storage Type             raft
HA Enabled               true
```

## Step 2: Initialize the First Node

Initialize Vault on **node 1 only**. This creates the encryption keys and root token.

```bash
# SSH to vault-node-1
ssh -i vault-ssh-key.pem vaultadmin@10.0.1.11

# Set environment
export VAULT_ADDR="http://127.0.0.1:8200"

# Initialize Vault with 5 key shares and 3 threshold
vault operator init -key-shares=5 -key-threshold=3
```

**Important**: Save the output securely! You will receive:
- 5 Unseal Keys
- 1 Initial Root Token

Example output:
```
Unseal Key 1: ABC123...
Unseal Key 2: DEF456...
Unseal Key 3: GHI789...
Unseal Key 4: JKL012...
Unseal Key 5: MNO345...

Initial Root Token: hvs.XXXXXXXXXXXXX

Vault initialized with 5 key shares and a key threshold of 3.
```

### Store Keys Securely

Store unseal keys in separate secure locations:
- Use Azure Key Vault secrets
- Distribute to different team members
- Never store all keys together

```bash
# Example: Store in Azure Key Vault
az keyvault secret set \
  --vault-name kv-vault-learn \
  --name vault-unseal-key-1 \
  --value "ABC123..."
```

## Step 3: Unseal the First Node

Unseal vault-node-1 using 3 of the 5 unseal keys:

```bash
# Run this 3 times with different keys
vault operator unseal
# Enter unseal key when prompted
```

After 3 keys, the node is unsealed:
```
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  false
Total Shares            5
Threshold               3
Version                 1.15.4
Cluster Name            vault-learn-cluster
Cluster ID              xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
HA Enabled              true
HA Cluster              https://10.0.1.11:8201
HA Mode                 active
Active Since            2024-01-15T10:30:00.000000Z
Raft Committed Index    50
Raft Applied Index      50
```

## Step 4: Unseal All Nodes

Each node must be unsealed individually:

We must use the same 3 unseal keys in direct order to Unseal the HashiCorp Vault Cluster 

```bash
# On vault-node-2
vault operator unseal  # Enter key 1
vault operator unseal  # Enter key 2
vault operator unseal  # Enter key 3

# On vault-node-3
vault operator unseal  # Enter key 1
vault operator unseal  # Enter key 2
vault operator unseal  # Enter key 3
```

## Step 6: Verify Cluster Status

### Check Raft Peers

```bash
# Authenticate first
vault login <root-token>

# List all Raft peers
vault operator raft list-peers
```

Expected output:
```
Node          Address            State       Voter
----          -------            -----       -----
vault-node-1  10.0.1.11:8201    leader      true
vault-node-2  10.0.1.12:8201    follower    true
vault-node-3  10.0.1.13:8201    follower    true
```

### Check Autopilot Status

```bash
vault operator raft autopilot state
```

Expected output:
```
vault operator raft autopilot state
Healthy:                         true
Failure Tolerance:               1
Leader:                          vault-node-1
Voters:
   vault-node-1
   vault-node-2
   vault-node-3
Servers:
   vault-node-1
      Name:              vault-node-1
      Address:           10.0.1.11:8201
      Status:            leader
      Node Status:       alive
      Healthy:           true
      Last Contact:      0s
      Last Term:         3
      Last Index:        63
      Version:           1.15.4
      Node Type:         voter
   vault-node-2
      Name:              vault-node-2
      Address:           10.0.1.12:8201
      Status:            voter
      Node Status:       alive
      Healthy:           true
      Last Contact:      531.098129ms
      Last Term:         3
      Last Index:        63
      Version:           1.15.4
      Node Type:         voter
   vault-node-3
      Name:              vault-node-3
      Address:           10.0.1.13:8201
      Status:            voter
      Node Status:       alive
      Healthy:           true
      Last Contact:      2.752165518s
      Last Term:         3
      Last Index:        63
      Version:           1.15.4
      Node Type:         voter

```

### Check HA Status

```bash
vault status
```

Look for:
- `HA Enabled: true`
- `HA Mode: active` (on leader) or `standby` (on followers)

## Step 7: Test Failover

### Simulate Leader Failure

```bash
# On the current leader node, stop Vault
sudo systemctl stop vault
```

### Verify New Leader Election

On another node:
```bash
vault operator raft list-peers
```

A new leader should be elected within seconds.

### Restore Failed Node

```bash
# Start Vault on the stopped node
sudo systemctl start vault

# Unseal the node
vault operator unseal  # 3 times
```

The node will rejoin as a follower.

### Security

1. **Rotate unseal keys** periodically
2. **Enable audit logging** on all nodes
3. **Restrict network access** to cluster ports
4. **Use TLS everywhere** including cluster communication

## Next Steps

- [04-auto-unseal.md](04-auto-unseal.md) - Configure Auto Unseal with Azure Key Vault
- [05-operations.md](05-operations.md) - Day-to-day Vault operations
- Set up [monitoring and alerting](05-operations.md#monitoring)
