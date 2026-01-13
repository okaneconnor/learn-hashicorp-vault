variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "uksouth"
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
  default     = "learning"
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "vaultadmin"
}

variable "vm_size" {
  description = "Size of the Vault VMs"
  type        = string
  default     = "Standard_B2s"
}

variable "vault_version" {
  description = "Version of HashiCorp Vault to install"
  type        = string
  default     = "1.15.4"
}

variable "vault_node_count" {
  description = "Number of Vault nodes in the cluster"
  type        = number
  default     = 3
}

variable "admin_source_address" {
  description = "Source IP address or CIDR for SSH access (e.g., your public IP)"
  type        = string
  default     = "*"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the Vault subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = "230414f6-3458-4f1a-9f5c-488281e13c14"
}