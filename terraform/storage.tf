# Storage Account for Custom Script Extension scripts
resource "azurerm_storage_account" "scripts" {
  name                     = "stvaultscripts"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.common_tags
}

# Storage Container for scripts
resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_id    = azurerm_storage_account.scripts.id
  container_access_type = "private"
}

# Upload install-vault.sh script
resource "azurerm_storage_blob" "install_vault" {
  name                   = "install-vault.sh"
  storage_account_name   = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/../scripts/install-vault.sh"
}

# SAS token for script access
data "azurerm_storage_account_sas" "scripts" {
  connection_string = azurerm_storage_account.scripts.primary_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "24h")

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}
