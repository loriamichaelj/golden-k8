# Azure network: a resource group holding a VNet with one subnet for the AKS
# nodes, and a NAT gateway for egress.
#
# Azure subnets span every zone of a region, so one node subnet serves all of
# them; zones are chosen per node pool. With Azure CNI overlay, pods and
# services get addresses outside the VNet, so the node subnet only holds nodes:
#   nodes  cidrsubnet(cidr, 2, 0)  /18 for a /16 (/22 for a /20)
#
# A subnet takes one NAT gateway, which Azure runs as a regional resource.
# natGateway single gives it one public IP; perZone gives it one public IP per
# zone in use, so egress capacity and addresses scale with the zones.

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.cidr, 2, 0)]

  # With a NAT gateway attached, nodes need no default outbound access.
  default_outbound_access_enabled = var.nat_gateway == "none"
}

resource "azurerm_public_ip" "nat" {
  count = var.nat_gateway == "none" ? 0 : (var.nat_gateway == "perZone" ? var.zone_count : 1)

  name                = "${var.name}-nat-${count.index}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count = var.nat_gateway == "none" ? 0 : 1

  name                    = var.name
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = length(azurerm_public_ip.nat)

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  count = var.nat_gateway == "none" ? 0 : 1

  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}
