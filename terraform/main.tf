# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-vault-learn-${var.location}"
  location = var.location

  tags = local.common_tags
}
