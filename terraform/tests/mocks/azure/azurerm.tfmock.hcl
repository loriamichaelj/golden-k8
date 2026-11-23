# Shared mock data for mock_provider "azurerm" (terraform test). The provider
# parses resource IDs even when mocked, so every ID referenced by another
# resource has a real Azure ID shape. Placeholder subscription and tenant
# 00000000-0000-0000-0000-000000000000.

mock_data "azurerm_client_config" {
  defaults = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
    object_id       = "11111111-1111-1111-1111-111111111111"
  }
}

mock_resource "azurerm_resource_group" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg"
  }
}

mock_resource "azurerm_virtual_network" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/virtualNetworks/golden-test"
  }
}

mock_resource "azurerm_subnet" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/virtualNetworks/golden-test/subnets/nodes"
  }
}

mock_resource "azurerm_public_ip" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/publicIPAddresses/golden-test-nat"
  }
}

mock_resource "azurerm_nat_gateway" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/natGateways/golden-test"
  }
}

mock_resource "azurerm_user_assigned_identity" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/golden-test"
    principal_id = "22222222-2222-2222-2222-222222222222"
    client_id    = "33333333-3333-3333-3333-333333333333"
  }
}

mock_resource "azurerm_kubernetes_cluster" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.ContainerService/managedClusters/golden-test"
    fqdn         = "golden-test-abcd1234.hcp.eastus.azmk8s.io"
    private_fqdn = "golden-test-abcd1234.privatelink.eastus.azmk8s.io"
  }
}
