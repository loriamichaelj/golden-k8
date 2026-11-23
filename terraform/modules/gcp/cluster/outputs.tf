output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL."
  value       = "https://${google_container_cluster.this.endpoint}"
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate."
  value       = try(google_container_cluster.this.master_auth[0].cluster_ca_certificate, "")
}

output "node_pools" {
  description = "Node pool settings per pool, as created."
  value = {
    for name, np in google_container_node_pool.this : name => {
      machine_type   = np.node_config[0].machine_type
      total_min      = np.autoscaling[0].total_min_node_count
      total_max      = np.autoscaling[0].total_max_node_count
      initial        = np.initial_node_count
      node_locations = np.node_locations
      labels         = np.node_config[0].labels
    }
  }
}

output "node_service_account" {
  description = "Service account the nodes run as."
  value       = google_service_account.nodes.email
}
