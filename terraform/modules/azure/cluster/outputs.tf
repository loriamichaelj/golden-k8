output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL."
  value       = "https://${azurerm_kubernetes_cluster.this.fqdn}:443"
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate."
  value       = try(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate, "")
  sensitive   = true
}

output "node_pools" {
  description = "Node pool settings per pool, as created (system pool first)."
  value = merge(
    {
      (azurerm_kubernetes_cluster.this.default_node_pool[0].name) = {
        mode    = "System"
        vm_size = azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size
        min     = azurerm_kubernetes_cluster.this.default_node_pool[0].min_count
        max     = azurerm_kubernetes_cluster.this.default_node_pool[0].max_count
        zones   = azurerm_kubernetes_cluster.this.default_node_pool[0].zones
        labels  = azurerm_kubernetes_cluster.this.default_node_pool[0].node_labels
      }
    },
    {
      for name, np in azurerm_kubernetes_cluster_node_pool.user : name => {
        mode    = np.mode
        vm_size = np.vm_size
        min     = np.min_count
        max     = np.max_count
        zones   = np.zones
        labels  = np.node_labels
      }
    }
  )
}

output "oidc_issuer_url" {
  description = "OIDC issuer for workload identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}
