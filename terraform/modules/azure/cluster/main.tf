# Azure cluster: AKS with Azure CNI overlay (Cilium data plane, so
# NetworkPolicies are enforced), Microsoft Entra ID auth with Azure RBAC and no
# local accounts, workload identity, a user-assigned control plane identity,
# and autoscaled node pools from spec.cluster.nodePools: the first is the
# system pool, the rest are user pools. The built-in Azure Disk CSI driver
# provides the managed-csi default StorageClass.

data "azurerm_client_config" "current" {}

locals {
  pools = [
    for p in var.node_pools : {
      name    = substr(replace(p.name, "-", ""), 0, 12)
      vm_size = p.instance_type
      min     = p.min
      max     = p.max
      labels  = { "golden-k8/pool" = p.name, "golden-k8/size" = p.size }
    }
  ]
  system_pool = local.pools[0]
  user_pools  = { for p in slice(local.pools, 1, length(local.pools)) : p.name => p }

  # Overlay ranges, outside the VNet (modules/azure/network rejects overlaps).
  pod_cidr       = "192.168.0.0/16"
  service_cidr   = "172.16.0.0/16"
  dns_service_ip = "172.16.0.10"
}

resource "azurerm_user_assigned_identity" "cluster" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# The control plane manages load balancers and NAT in the VNet.
resource "azurerm_role_assignment" "cluster_network" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  default_node_pool {
    name                        = local.system_pool.name
    vm_size                     = local.system_pool.vm_size
    os_sku                      = "AzureLinux"
    zones                       = var.zones
    vnet_subnet_id              = var.node_subnet_id
    auto_scaling_enabled        = true
    min_count                   = local.system_pool.min
    max_count                   = local.system_pool.max
    node_count                  = local.system_pool.min
    node_labels                 = local.system_pool.labels
    node_public_ip_enabled      = !var.private_nodes
    temporary_name_for_rotation = "tmprotation"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Node pools are declared here, not auto-provisioned (node auto-provisioning is "Auto").
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = local.pod_cidr
    service_cidr        = local.service_cidr
    dns_service_ip      = local.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = var.nat_gateway == "none" ? "loadBalancer" : "userAssignedNATGateway"
  }

  # Entra ID sign-in with Azure RBAC; no static admin credentials.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  dynamic "api_server_access_profile" {
    for_each = length(var.authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.authorized_ip_ranges
    }
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.cluster_network]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = local.user_pools

  name                   = each.key
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.this.id
  mode                   = "User"
  vm_size                = each.value.vm_size
  os_sku                 = "AzureLinux"
  zones                  = var.zones
  vnet_subnet_id         = var.node_subnet_id
  auto_scaling_enabled   = true
  min_count              = each.value.min
  max_count              = each.value.max
  node_count             = each.value.min
  node_labels            = each.value.labels
  node_public_ip_enabled = !var.private_nodes
  tags                   = var.tags

  upgrade_settings {
    max_surge = "10%"
  }

  lifecycle {
    # The cluster autoscaler owns the node count after creation.
    ignore_changes = [node_count]
  }
}

# Whoever applies becomes cluster admin (Azure RBAC), like EKS's creator admin.
resource "azurerm_role_assignment" "admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
