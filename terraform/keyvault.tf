# Azure Key Vault for storing SSH keys and secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-vault-learn"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = true
  rbac_authorization_enabled = true
  tags                       = local.common_tags
}

# Role assignment for current user to manage secrets
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Generate SSH key pair for VM access
resource "tls_private_key" "vault_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store SSH private key in Key Vault
resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "vault-vm-ssh-private-key"
  value        = tls_private_key.vault_ssh.private_key_pem
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Store SSH public key in Key Vault
resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "vault-vm-ssh-public-key"
  value        = tls_private_key.vault_ssh.public_key_openssh
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Key for Vault Auto Unseal
resource "azurerm_key_vault_key" "vault_unseal" {
  name         = "vault-unseal-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]

  depends_on = [azurerm_role_assignment.keyvault_admin]
}
