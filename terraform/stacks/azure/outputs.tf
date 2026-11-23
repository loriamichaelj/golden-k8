output "contract" {
  description = "Outputs contract (see modules/contract)."
  value       = module.contract.contract
}

output "app_url" {
  description = "Where the sample app will be reachable once deployed (point DNS at the load balancer)."
  value       = "http://${local.spec.app.expose.host}"
}

output "network" {
  description = "Resource group, zones, node subnet and NAT in use."
  value = {
    resource_group = module.network.resource_group_name
    zones          = module.network.zones
    node_subnet    = module.network.node_subnet_cidr
    nat            = module.network.nat
  }
}

output "node_pools" {
  description = "Node pool settings per pool (system pool first)."
  value       = module.cluster.node_pools
}
