output "network_id" {
  description = "VPC network ID."
  value       = google_compute_network.this.id
}

output "subnetwork_id" {
  description = "Node subnet ID."
  value       = google_compute_subnetwork.nodes.id
}

output "zones" {
  description = "Zones the cluster spreads nodes across."
  value       = local.zones
}

output "ranges" {
  description = "Node, pod and service ranges."
  value = {
    nodes    = local.nodes_cidr
    pods     = local.pods_cidr
    services = local.services_cidr
  }
}

output "pods_range_name" {
  description = "Secondary range name for pods."
  value       = local.pods_range_name
}

output "services_range_name" {
  description = "Secondary range name for services."
  value       = local.services_range_name
}

output "nat" {
  description = "Cloud NAT gateways and their static addresses (none for auto-allocated IPs)."
  value = {
    gateways      = length(google_compute_router_nat.this)
    static_ips    = length(google_compute_address.nat)
    ip_allocation = try(google_compute_router_nat.this[0].nat_ip_allocate_option, null)
  }
}
