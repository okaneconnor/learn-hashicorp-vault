# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-vault-learn"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_address_space]
  tags                = local.common_tags
}

# Subnet for Vault nodes
resource "azurerm_subnet" "vault" {
  name                 = "snet-vault-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group for Vault nodes
resource "azurerm_network_security_group" "vault" {
  name                = "nsg-vault-nodes"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# NSG Rule: Allow SSH from admin source
resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "AllowSSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.admin_source_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.vault.name
}

# NSG Rule: Allow Vault API (8200) from VNet
resource "azurerm_network_security_rule" "allow_vault_api" {
  name                        = "AllowVaultAPI"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8200"
  source_address_prefix       = var.vnet_address_space
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.vault.name
}

# NSG Rule: Allow Vault Cluster/Raft communication (8201) within subnet
resource "azurerm_network_security_rule" "allow_vault_cluster" {
  name                        = "AllowVaultCluster"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8201"
  source_address_prefix       = var.subnet_address_prefix
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.vault.name
}

# NSG Rule: Allow HTTPS outbound for package updates
resource "azurerm_network_security_rule" "allow_https_outbound" {
  name                        = "AllowHTTPSOutbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.vault.name
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "vault" {
  subnet_id                 = azurerm_subnet.vault.id
  network_security_group_id = azurerm_network_security_group.vault.id
}
