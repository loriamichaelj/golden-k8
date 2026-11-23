# Mocked AzureRM provider (shared mocks in terraform/tests/mocks/azure): no
# credentials, no API calls, no cost.

mock_provider "azurerm" {
  source = "../../../tests/mocks/azure"
}

variables {
  name        = "golden-test"
  location    = "eastus"
  cidr        = "10.20.0.0/16"
  zone_count  = 3
  nat_gateway = "single"
}

run "single_nat" {
  assert {
    condition     = output.resource_group_name == "golden-test-rg" && output.location == "eastus"
    error_message = "resource group should be <cluster>-rg in the region"
  }
  assert {
    condition     = output.node_subnet_cidr == "10.20.0.0/18"
    error_message = "node subnet should be the first /18 of a /16"
  }
  assert {
    condition     = output.nat.gateways == 1 && output.nat.public_ips == 1
    error_message = "natGateway single: one NAT gateway with one public IP"
  }
  assert {
    condition     = length(azurerm_subnet_nat_gateway_association.nodes) == 1 && !azurerm_subnet.nodes.default_outbound_access_enabled
    error_message = "the node subnet should egress through the NAT gateway only"
  }
  assert {
    condition     = jsonencode(output.zones) == jsonencode(["1", "2", "3"])
    error_message = "azCount 3 should use zones 1-3"
  }
}

run "nat_per_zone" {
  variables {
    zone_count  = 2
    nat_gateway = "perZone"
  }

  assert {
    condition     = output.nat.gateways == 1 && output.nat.public_ips == 2 && length(azurerm_nat_gateway_public_ip_association.this) == 2
    error_message = "natGateway perZone: one NAT gateway with one public IP per zone"
  }
}

run "no_nat" {
  variables {
    zone_count  = 1
    nat_gateway = "none"
  }

  assert {
    condition     = output.nat.gateways == 0 && output.nat.public_ips == 0 && output.nat_gateway_id == null
    error_message = "natGateway none: no NAT gateway"
  }
  assert {
    condition     = azurerm_subnet.nodes.default_outbound_access_enabled
    error_message = "without NAT the subnet keeps default outbound access"
  }
}

run "smallest_vnet" {
  variables { cidr = "10.30.0.0/20" }

  assert {
    condition     = output.node_subnet_cidr == "10.30.0.0/22"
    error_message = "a /20 VNet should get a /22 node subnet"
  }
}

run "overlaps_pod_range" {
  command = plan
  variables { cidr = "192.168.0.0/16" }
  expect_failures = [var.cidr]
}

run "overlaps_service_range" {
  command = plan
  variables { cidr = "172.16.16.0/20" }
  expect_failures = [var.cidr]
}
