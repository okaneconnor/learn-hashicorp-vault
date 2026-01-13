# Auto Unseal with Azure Key Vault

This guide covers configuring HashiCorp Vault to automatically unseal using Azure Key Vault, eliminating the need for manual unseal key entry after restarts.

## Overview

### What is Auto Unseal?

Auto Unseal moves the responsibility of protecting the root key from Vault operators to a trusted cloud provider. Instead of requiring 3 of 5 unseal keys to reconstruct the master key, Vault uses Azure Key Vault to automatically decrypt the master key on startup.

### Shamir vs Auto Unseal Comparison

| Aspect | Shamir (Manual) | Auto Unseal |
|--------|-----------------|-------------|
| **Startup** | Requires 3+ operators to enter keys | Automatic, no human intervention |
| **Key Storage** | Distributed among operators | Delegated to Azure Key Vault |
| **Recovery** | Recovery uses same unseal keys | Recovery keys generated (different from unseal) |
| **Availability** | Depends on operator availability | Depends on Azure Key Vault availability |
| **Use Case** | High-security environments, air-gapped | Production automation, HA clusters |

### Architecture with Auto Unseal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Azure Subscription                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Azure Key Vault (kv-vault-learn)               │   │
│  │                                                                    │   │
│  │    ┌─────────────────────────────────────────────────────────┐   │   │
│  │    │  vault-unseal-key (RSA 2048)                            │   │   │
│  │    │  - wrapKey / unwrapKey operations                       │   │   │
│  │    └─────────────────────────────────────────────────────────┘   │   │
│  │                              ▲                                    │   │
│  │                              │ Key Vault Crypto User             │   │
│  └──────────────────────────────┼────────────────────────────────────┘   │
│                                 │                                        │
│  ┌──────────────────────────────┼────────────────────────────────────┐   │
│  │                    Managed Identity (id-vault-unseal)             │   │
│  │                              │                                    │   │
│  └──────────────────────────────┼────────────────────────────────────┘   │
│                                 │                                        │
│  ┌──────────────────────────────┴────────────────────────────────────┐   │
│  │                       Vault Raft Cluster                          │   │
│  │                                                                    │   │
│  │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │   │
│  │   │ vault-node-1│    │ vault-node-2│    │ vault-node-3│          │   │
│  │   │   (Leader)  │◄──►│  (Follower) │◄──►│  (Follower) │          │   │
│  │   │ 10.0.1.11   │    │ 10.0.1.12   │    │ 10.0.1.13   │          │   │
│  │   └─────────────┘    └─────────────┘    └─────────────┘          │   │
│  │                                                                    │   │
│  │   On startup, each node:                                          │   │
│  │   1. Uses Managed Identity to authenticate to Key Vault           │   │
│  │   2. Requests unwrapKey operation on vault-unseal-key            │   │
│  │   3. Decrypts master key and unseals automatically               │   │
│  │                                                                    │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

| Term | Description |
|------|-------------|
| **Recovery Keys** | Keys generated during Auto Unseal init; used for recovery operations, NOT for unsealing |
| **Seal Migration** | Process of converting from Shamir unseal to Auto Unseal (or vice versa) |
| **Managed Identity** | Azure identity attached to VMs; provides automatic authentication to Key Vault |
| **Key Vault Crypto User** | Azure RBAC role granting wrapKey/unwrapKey permissions |
| **Root Key** | The key that encrypts all Vault data; protected by the seal mechanism |

## Prerequisites

Before starting, ensure:
- [ ] Completed [03-raft-cluster.md](03-raft-cluster.md) - working 3-node cluster with Shamir unseal
- [ ] Have your 5 unseal keys available (needed for migration)
- [ ] Terraform applied with Auto Unseal resources (managed identity, Key Vault key)
- [ ] Azure CLI installed and authenticated (`az login`)

## Part 1: Verify Infrastructure

Before configuring Vault, verify the Terraform infrastructure is deployed correctly.

### Step 1.1: Check Terraform Outputs

Run these commands from the `terraform/` directory:

```bash
cd terraform

# View all auto-unseal related outputs
terraform output vault_unseal_key_name
terraform output vault_managed_identity_client_id
terraform output azure_tenant_id

# Get the full configuration snippet
terraform output auto_unseal_vault_config
```

Expected output:
```
vault_unseal_key_name = "vault-unseal-key"
vault_managed_identity_client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

auto_unseal_vault_config = <<EOT
  seal "azurekeyvault" {
    tenant_id  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    vault_name = "kv-vault-learn"
    key_name   = "vault-unseal-key"
  }
EOT
```

**Save these values** - you'll need them to configure Vault.

### Step 1.2: Verify Key Vault Key Exists

```bash
# List keys in Key Vault
az keyvault key list --vault-name kv-vault-learn --query "[].name" -o tsv
```

Expected output should include:
```
vault-unseal-key
```

### Step 1.3: Verify Managed Identity on VMs

SSH to any Vault node and verify the managed identity is attached:

```bash
# First, get SSH key from Key Vault
az keyvault secret show \
  --vault-name kv-vault-learn \
  --name vault-vm-ssh-private-key \
  --query value \
  -o tsv > ~/.ssh/vault-vm-key.pem

chmod 600 ~/.ssh/vault-vm-key.pem

# SSH to vault-node-1 (replace with actual public IP from terraform output)
ssh -i ~/.ssh/vault-vm-key.pem vaultadmin@<PUBLIC_IP>
```

Once connected, test the managed identity can authenticate:

```bash
# Request a token for Azure Key Vault
curl -s -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" \
  | jq .access_token

# If successful, you'll see a JWT token (long string starting with "eyJ...")
# If failed, you'll see an error message
```

If you see a token, the managed identity is working correctly.

## Part 2: Configure Auto Unseal

Now we'll migrate each Vault node from Shamir unseal to Azure Key Vault Auto Unseal.

**Important**: Perform these steps on ONE node at a time, starting with the leader.

### Step 2.1: Identify the Current Leader

```bash
# Set environment
export VAULT_ADDR="http://127.0.0.1:8200"

# Check which node is the leader
vault status | grep "HA Mode"
```

Output showing `active` means this is the leader:
```
HA Mode                 active
```

Start with the leader node first.

### Step 2.2: Stop Vault Service

```bash
sudo systemctl stop vault
```

### Step 2.3: Backup Current Configuration (Recommended)

```bash
sudo cp /etc/vault.d/vault.hcl /etc/vault.d/vault.hcl.backup
```

### Step 2.4: Edit Vault Configuration

Open the Vault configuration file:

```bash
sudo nano /etc/vault.d/vault.hcl
```

Add the following `seal` stanza at the end of the file. Replace the values with your Terraform outputs:

```hcl
# Auto Unseal with Azure Key Vault
seal "azurekeyvault" {
  tenant_id  = "<YOUR_TENANT_ID>"
  vault_name = "kv-vault-learn"
  key_name   = "vault-unseal-key"
}
```

**Note**: You do NOT need `client_id` or `client_secret` - the managed identity handles authentication automatically.

Your complete configuration should look like:

```hcl
ui = true
disable_mlock = true

cluster_name = "vault-learn-cluster"
cluster_addr = "http://10.0.1.11:8201"
api_addr     = "http://10.0.1.11:8200"

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-1"

  retry_join {
    leader_api_addr = "http://10.0.1.11:8200"
  }
  retry_join {
    leader_api_addr = "http://10.0.1.12:8200"
  }
  retry_join {
    leader_api_addr = "http://10.0.1.13:8200"
  }
}

# Auto Unseal with Azure Key Vault
seal "azurekeyvault" {
  tenant_id  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  vault_name = "kv-vault-learn"
  key_name   = "vault-unseal-key"
}
```

Save and exit (Ctrl+X, Y, Enter in nano).

### Step 2.5: Start Vault and Perform Seal Migration

Start the Vault service:

```bash
sudo systemctl start vault
```

Check the status - it will show migration is required:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
vault status
```

Expected output:
```
Key                           Value
---                           -----
Recovery Seal Type            azurekeyvault
Initialized                   true
Sealed                        true
Total Recovery Shares         0
Threshold                     0
Unseal Progress               0/3
Unseal Nonce                  n/a
Seal Migration in Progress    true
Version                       1.15.4
Build Date                    2023-12-04T17:45:28Z
Storage Type                  raft
HA Enabled                    true
```

Notice `Seal Migration in Progress: true`.

### Step 2.6: Complete Seal Migration with Unseal Keys

You must provide your existing Shamir unseal keys to complete the migration:

```bash
vault operator unseal -migrate
# Enter unseal key 1 when prompted

vault operator unseal -migrate
# Enter unseal key 2 when prompted

vault operator unseal -migrate
# Enter unseal key 3 when prompted
```

After providing 3 keys (threshold), the migration completes:

```
Key                           Value
---                           -----
Recovery Seal Type            shamir
Initialized                   true
Sealed                        false
Total Recovery Shares         5
Threshold                     3
Version                       1.15.4
Build Date                    2023-12-04T17:45:28Z
Storage Type                  raft
Cluster Name                  vault-learn-cluster
Cluster ID                    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
HA Enabled                    true
HA Cluster                    http://10.0.1.11:8201
HA Mode                       active
Active Since                  2024-01-15T12:00:00.000000Z
Raft Committed Index          150
Raft Applied Index            150
```

**Important**: Your original unseal keys have been converted to **recovery keys**. They can no longer unseal Vault but are needed for certain recovery operations.

### Step 2.7: Verify Auto Unseal is Working

```bash
vault status
```

Look for:
- `Sealed: false` - Vault is unsealed
- No `Unseal Progress` line - Auto Unseal is active

### Step 2.8: Repeat for Remaining Nodes

Repeat Steps 2.2 through 2.7 on each remaining node (vault-node-2, vault-node-3).

For follower nodes, the migration process is the same:
1. Stop Vault
2. Edit configuration to add seal stanza
3. Start Vault
4. Run `vault operator unseal -migrate` three times with unseal keys

## Part 3: Verification

After all nodes are migrated, verify the cluster is healthy.

### Step 3.1: Check Cluster Status

```bash
# Login with root token
vault login <root-token>

# Check Raft peers
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

### Step 3.2: Check Autopilot Health

```bash
vault operator raft autopilot state
```

Verify `Healthy: true` in the output.

### Step 3.3: Verify Seal Type

On each node, check the seal type:

```bash
vault status | grep -E "(Seal Type|Recovery)"
```

Expected output:
```
Recovery Seal Type            shamir
```

This confirms Vault is using Azure Key Vault for unsealing, with Shamir recovery keys.

## Part 4: Testing Auto Unseal

### Test 1: Restart a Single Node

```bash
# On vault-node-2 (or any follower)
sudo systemctl restart vault

# Wait a few seconds, then check status
sleep 5
vault status
```

The node should be **automatically unsealed** without any manual intervention:
```
Sealed                        false
```

### Test 2: Restart the Leader

```bash
# On the current leader
sudo systemctl restart vault

# Wait for leader election and check status
sleep 10
vault operator raft list-peers
```

A new leader should be elected, and the restarted node should automatically unseal and rejoin.

### Test 3: Restart All Nodes

To fully test Auto Unseal, restart all nodes:

```bash
# On vault-node-1
sudo systemctl restart vault

# On vault-node-2
sudo systemctl restart vault

# On vault-node-3
sudo systemctl restart vault
```

Wait 30 seconds, then verify from any node:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
vault status
vault operator raft list-peers
```

All nodes should be unsealed and healthy without any manual unseal operations.

## Troubleshooting

### Error: "error authenticating to Azure"

**Cause**: Managed identity not properly attached or configured.

**Solution**:
1. Verify managed identity is attached to the VM:
   ```bash
   curl -s -H "Metadata: true" \
     "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"
   ```
2. If you see an error, check Terraform deployment for the identity attachment.

### Error: "error wrapping/unwrapping key"

**Cause**: Missing Key Vault permissions.

**Solution**:
1. Verify the role assignment in Azure:
   ```bash
   az role assignment list --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/kv-vault-learn --query "[?principalType=='ServicePrincipal']"
   ```
2. Ensure `Key Vault Crypto User` role is assigned to the managed identity.

### Error: "key not found"

**Cause**: Key Vault key doesn't exist or wrong name in configuration.

**Solution**:
1. Verify the key exists:
   ```bash
   az keyvault key show --vault-name kv-vault-learn --name vault-unseal-key
   ```
2. Check the `key_name` in your Vault configuration matches exactly.

### Vault Logs

Check Vault logs for detailed error messages:

```bash
sudo journalctl -u vault -f
```

### Azure Activity Logs

Check Azure Key Vault activity for access attempts:

```bash
az monitor activity-log list \
  --resource-group rg-vault-learn-uksouth \
  --resource-type Microsoft.KeyVault/vaults \
  --query "[].{Time:eventTimestamp, Operation:operationName.value, Status:status.value}" \
  -o table
```

## Security Considerations

### Recovery Key Management

1. **Store recovery keys securely** - They're needed for:
   - Generating a new root token
   - Recovering from certain failure scenarios
   - Migrating back to Shamir unseal

2. **Recovery keys are NOT unseal keys** - Don't confuse them. Recovery keys cannot unseal Vault when Auto Unseal is configured.

### Key Vault Security

1. **Enable Key Vault logging** - Monitor access to the unseal key
2. **Use private endpoints** (production) - Restrict network access to Key Vault
3. **Enable soft delete and purge protection** - Already configured in this setup
4. **Rotate the unseal key periodically** - Follow HashiCorp's key rotation guidance

### Managed Identity Security

1. **Use User-Assigned Identity** - Provides better audit trail than System-Assigned
2. **Principle of least privilege** - Only grant `Key Vault Crypto User`, not broader permissions
3. **Monitor identity usage** - Use Azure AD logs to track authentication events

## Next Steps

- [05-operations.md](05-operations.md) - Day-to-day Vault operations
- Enable [audit logging](05-operations.md#audit-logging) to track all Vault operations
- Configure [authentication methods](05-operations.md#authentication) for users and applications
