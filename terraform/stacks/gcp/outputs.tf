output "contract" {
  description = "Outputs contract (see modules/contract)."
  value       = module.contract.contract
}

output "app_url" {
  description = "Where the sample app will be reachable once deployed (point DNS at the load balancer)."
  value       = "http://${local.spec.app.expose.host}"
}

output "network" {
  description = "Zones, ranges and NAT in use."
  value = {
    zones  = module.network.zones
    ranges = module.network.ranges
    nat    = module.network.nat
  }
}

output "node_pools" {
  description = "Node pool settings per pool."
  value       = module.cluster.node_pools
}
