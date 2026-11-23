output "resource_group_name" {
  description = "Resource group holding the network and the cluster."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region."
  value       = azurerm_resource_group.this.location
}

output "vnet_id" {
  description = "VNet ID."
  value       = azurerm_virtual_network.this.id
}

output "node_subnet_id" {
  description = "Node subnet ID."
  value       = azurerm_subnet.nodes.id
}

output "node_subnet_cidr" {
  description = "Node subnet range."
  value       = azurerm_subnet.nodes.address_prefixes[0]
}

output "zones" {
  description = "Availability zones in use (Azure numbers them 1-3 in every zonal region)."
  value       = [for i in range(var.zone_count) : tostring(i + 1)]
}

output "nat" {
  description = "NAT gateways and their public IPs."
  value = {
    gateways   = length(azurerm_nat_gateway.this)
    public_ips = length(azurerm_public_ip.nat)
  }
}

output "nat_gateway_id" {
  description = "NAT gateway ID (null without one)."
  value       = try(azurerm_nat_gateway.this[0].id, null)
}
