# Mocked AzureRM provider (shared mocks in terraform/tests/mocks/azure): no
# credentials, no API calls, no cost.

mock_provider "azurerm" {
  source = "../../../tests/mocks/azure"
}

variables {
  name                = "golden-test"
  resource_group_name = "golden-test-rg"
  location            = "eastus"
  kubernetes_version  = "1.36"
  vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/virtualNetworks/golden-test"
  node_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/virtualNetworks/golden-test/subnets/nodes"
  zones               = ["1", "2", "3"]
  nat_gateway         = "single"
  private_nodes       = true
  node_pools = [
    { name = "system", size = "small", min = 2, max = 3, instance_type = "Standard_D2s_v5" },
    { name = "apps-batch", size = "medium", min = 1, max = 5, instance_type = "Standard_D4s_v5" },
  ]
}

run "system_and_user_pools" {
  assert {
    condition     = toset(keys(output.node_pools)) == toset(["system", "appsbatch"])
    error_message = "first pool is the system pool, the rest user pools; names lose dashes"
  }
  assert {
    condition = (
      output.node_pools.system.mode == "System" && output.node_pools.system.vm_size == "Standard_D2s_v5" &&
      output.node_pools.system.min == 2 && output.node_pools.system.max == 3
    )
    error_message = "system pool: small → Standard_D2s_v5, min 2, max 3"
  }
  assert {
    condition = (
      output.node_pools.appsbatch.mode == "User" && output.node_pools.appsbatch.vm_size == "Standard_D4s_v5" &&
      output.node_pools.appsbatch.max == 5
    )
    error_message = "apps-batch pool: User mode, medium → Standard_D4s_v5, max 5"
  }
  assert {
    condition     = output.node_pools.appsbatch.labels["golden-k8/pool"] == "apps-batch" && output.node_pools.system.labels["golden-k8/size"] == "small"
    error_message = "node labels keep the original pool name and size"
  }
  assert {
    condition     = jsonencode(output.node_pools.system.zones) == jsonencode(["1", "2", "3"])
    error_message = "pools should span the zones"
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled &&
      !azurerm_kubernetes_cluster.this.default_node_pool[0].node_public_ip_enabled &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].os_sku == "AzureLinux"
    )
    error_message = "autoscaled Azure Linux nodes without public IPs"
  }
}

run "cluster_settings" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled && output.cluster_endpoint == "https://golden-test-abcd1234.privatelink.eastus.azmk8s.io:443"
    error_message = "private cluster by default; cluster_endpoint should be the private FQDN"
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay" &&
      azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium" &&
      azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "userAssignedNATGateway"
    )
    error_message = "Azure CNI overlay with Cilium policy, egress through the NAT gateway"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled && azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    error_message = "Entra ID with Azure RBAC, no local accounts"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled && azurerm_kubernetes_cluster.this.oidc_issuer_enabled
    error_message = "workload identity needs the OIDC issuer"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].type == "UserAssigned" && azurerm_role_assignment.cluster_network.role_definition_name == "Network Contributor"
    error_message = "user-assigned control plane identity with Network Contributor on the VNet"
  }
  assert {
    condition     = azurerm_role_assignment.admin.role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin" && azurerm_role_assignment.admin.principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "whoever applies should become cluster admin"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this.api_server_access_profile) == 0 && azurerm_kubernetes_cluster.this.sku_tier == "Free"
    error_message = "no API server IP restriction and Free tier by default"
  }
}

run "public_nodes_and_overrides" {
  variables {
    nat_gateway          = "none"
    private_nodes        = false
    authorized_ip_ranges = ["203.0.113.0/24"]
    sku_tier             = "Standard"
    node_pools           = [{ name = "system", size = "large", min = 1, max = 2, instance_type = "Standard_D8s_v5" }]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "loadBalancer" && azurerm_kubernetes_cluster.this.default_node_pool[0].node_public_ip_enabled
    error_message = "natGateway none: egress through the cluster load balancer; public nodes when asked"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user) == 0
    error_message = "a single pool is only the system pool"
  }
  assert {
    condition     = jsonencode(tolist(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges)) == jsonencode(["203.0.113.0/24"]) && azurerm_kubernetes_cluster.this.sku_tier == "Standard"
    error_message = "authorized IP ranges and tier from the overrides"
  }
  assert {
    condition     = !azurerm_kubernetes_cluster.this.private_cluster_enabled && output.cluster_endpoint == "https://golden-test-abcd1234.hcp.eastus.azmk8s.io:443"
    error_message = "with authorized ranges the API server is public, at the public FQDN"
  }
}

run "pool_names_collide" {
  command = plan
  variables {
    node_pools = [
      { name = "apps-a", size = "small", min = 1, max = 2, instance_type = "Standard_D2s_v5" },
      { name = "appsa", size = "small", min = 1, max = 2, instance_type = "Standard_D2s_v5" },
    ]
  }
  expect_failures = [var.node_pools]
}

run "pool_min_over_max" {
  command = plan
  variables {
    node_pools = [{ name = "system", size = "small", min = 4, max = 3, instance_type = "Standard_D2s_v5" }]
  }
  expect_failures = [var.node_pools]
}
