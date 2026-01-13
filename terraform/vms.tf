# User-Assigned Managed Identity for Vault Auto Unseal
resource "azurerm_user_assigned_identity" "vault" {
  name                = "id-vault-unseal"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Role Assignment - Key Vault Crypto User for Auto Unseal
resource "azurerm_role_assignment" "vault_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.vault.principal_id
}

# Public IPs for Vault nodes
resource "azurerm_public_ip" "vault" {
  for_each = local.vault_nodes

  name                = "pip-${each.value.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

# Network Interfaces for Vault nodes
resource "azurerm_network_interface" "vault" {
  for_each = local.vault_nodes

  name                = "nic-${each.value.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vault.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = azurerm_public_ip.vault[each.key].id
  }

  tags = local.common_tags
}

# Vault Virtual Machines
resource "azurerm_linux_virtual_machine" "vault" {
  for_each = local.vault_nodes

  name                            = each.value.name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.vault[each.key].id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vault_ssh.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-${each.value.name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # Managed Identity for Azure Key Vault Auto Unseal
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vault.id]
  }

  tags = local.common_tags
}

# Custom Script Extension to install and configure Vault
resource "azurerm_virtual_machine_extension" "vault_install" {
  for_each = local.vault_nodes

  name                 = "vault-install"
  virtual_machine_id   = azurerm_linux_virtual_machine.vault[each.key].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  settings = jsonencode({
    fileUris = [
      "${azurerm_storage_blob.install_vault.url}${data.azurerm_storage_account_sas.scripts.sas}"
    ]
  })

  protected_settings = jsonencode({
    commandToExecute = "bash install-vault.sh ${each.value.node_id} '${join(",", [for node in local.vault_nodes : node.private_ip])}' ${var.vault_version}"
  })

  tags = local.common_tags

  depends_on = [
    azurerm_linux_virtual_machine.vault,
    azurerm_storage_blob.install_vault
  ]
}
