# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

# Networking
output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "ID of the Vault subnet"
  value       = azurerm_subnet.vault.id
}

# Key Vault
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Vault Nodes
output "vault_node_private_ips" {
  description = "Private IP addresses of the Vault nodes"
  value = {
    for key, node in local.vault_nodes : key => node.private_ip
  }
}

output "vault_node_public_ips" {
  description = "Public IP addresses of the Vault nodes"
  value = {
    for key, pip in azurerm_public_ip.vault : key => pip.ip_address
  }
}

output "vault_node_names" {
  description = "Names of the Vault VM nodes"
  value = {
    for key, node in local.vault_nodes : key => node.name
  }
}

# SSH Access
output "ssh_private_key_secret_name" {
  description = "Name of the Key Vault secret containing the SSH private key"
  value       = azurerm_key_vault_secret.ssh_private_key.name
}

output "ssh_commands" {
  description = "SSH commands to connect to each Vault node"
  value = {
    for key, pip in azurerm_public_ip.vault : key => "ssh -i ~/.ssh/vault-vm-key.pem ${var.admin_username}@${pip.ip_address}"
  }
}

# Vault Access
output "vault_api_addresses" {
  description = "Vault API addresses for each node"
  value = {
    for key, node in local.vault_nodes : key => "https://${node.private_ip}:8200"
  }
}

# Auto Unseal Configuration
output "vault_unseal_key_name" {
  description = "Azure Key Vault key name for auto-unseal"
  value       = azurerm_key_vault_key.vault_unseal.name
}

output "vault_managed_identity_client_id" {
  description = "Client ID of the managed identity for Vault VMs"
  value       = azurerm_user_assigned_identity.vault.client_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID for Vault auto-unseal"
  value       = data.azurerm_client_config.current.tenant_id
}

output "auto_unseal_vault_config" {
  description = "Vault seal configuration snippet for auto-unseal"
  value       = <<-EOT
    seal "azurekeyvault" {
      tenant_id  = "${data.azurerm_client_config.current.tenant_id}"
      vault_name = "${azurerm_key_vault.main.name}"
      key_name   = "${azurerm_key_vault_key.vault_unseal.name}"
    }
  EOT
}
