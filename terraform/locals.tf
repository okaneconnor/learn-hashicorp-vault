locals {
  # Common tags for all resources
  common_tags = {
    environment = var.environment
    project     = "learn-hashicorp-vault"
    managed_by  = "terraform"
  }

  # Vault node configuration
  vault_nodes = {
    for i in range(1, var.vault_node_count + 1) : "vault-node-${i}" => {
      node_id    = i
      name       = "vm-vault-node-${i}"
      private_ip = cidrhost(var.subnet_address_prefix, 10 + i)
    }
  }

  # Cluster peer addresses for Raft join configuration
  cluster_peers = [for node in local.vault_nodes : "https://${node.private_ip}:8200"]
}
