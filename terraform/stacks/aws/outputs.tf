output "contract" {
  description = "Outputs contract (see modules/contract)."
  value       = module.contract.contract
}

output "app_url" {
  description = "Where the sample app will be reachable once deployed (point DNS at the load balancer)."
  value       = "http://${local.spec.app.expose.host}"
}

output "network" {
  description = "Zones and subnets in use."
  value = {
    azs                = module.network.azs
    public_subnet_ids  = module.network.public_subnet_ids
    private_subnet_ids = module.network.private_subnet_ids
    nat_gateway_ids    = module.network.nat_gateway_ids
  }
}

output "node_groups" {
  description = "Managed node group settings per pool."
  value       = module.cluster.node_groups
}
