# provider: azure — a VNet and an AKS cluster. Validated and mock-tested only:
# golden-k8 never provisions cloud resources (spec.pipeline.apply stays false).

locals {
  config   = jsondecode(file(var.config_path))
  spec     = local.config.spec
  platform = yamldecode(file("${path.module}/platform.yaml"))

  cluster_name = "golden-${local.config.metadata.name}"
  overrides    = try(local.spec.cluster.providerOverrides, {})

  # Set on every taggable resource (azurerm has no provider-level default
  # tags). Azure tag names allow no "/", hence golden-k8-*.
  tags = merge(local.config.metadata.tags, {
    "golden-k8-environment" = local.config.metadata.name
    "golden-k8-owner"       = local.config.metadata.owner
    "golden-k8-managed"     = "true"
  })

  lb_annotations = merge(local.platform.lb_annotations, try(local.overrides.lbAnnotations, {}))
}

# The subscription comes from providerOverrides.subscriptionId, else from the
# environment (ARM_SUBSCRIPTION_ID, or the Azure CLI's current subscription).
provider "azurerm" {
  features {}
  subscription_id = try(local.overrides.subscriptionId, null)
}

module "sizing" {
  source     = "../../modules/sizing"
  cloud      = "azure"
  node_pools = local.spec.cluster.nodePools
}

module "network" {
  source = "../../modules/azure/network"

  name        = local.cluster_name
  location    = local.spec.region
  cidr        = local.spec.network.cidr
  zone_count  = local.spec.network.azCount
  nat_gateway = local.spec.network.natGateway
  tags        = local.tags
}

module "cluster" {
  source = "../../modules/azure/cluster"

  name                 = local.cluster_name
  resource_group_name  = module.network.resource_group_name
  location             = module.network.location
  kubernetes_version   = local.spec.cluster.version
  vnet_id              = module.network.vnet_id
  node_subnet_id       = module.network.node_subnet_id
  zones                = module.network.zones
  nat_gateway          = local.spec.network.natGateway
  private_nodes        = local.spec.network.privateSubnets
  node_pools           = module.sizing.node_pools
  authorized_ip_ranges = try(local.overrides.authorizedIpRanges, [])
  sku_tier             = try(local.overrides.skuTier, "Free")
  tags                 = local.tags
}

# Exec-based kubeconfig: no credentials in the file, Entra ID tokens come from
# kubelogin using the Azure CLI sign-in. 6dae42f8-... is the fixed Entra ID
# application of the AKS API server.
resource "local_file" "kubeconfig" {
  filename        = "${var.build_dir}/kubeconfig-${local.cluster_name}"
  file_permission = "0600"
  content = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = local.cluster_name
    clusters        = [{ name = local.cluster_name, cluster = { server = module.cluster.cluster_endpoint, certificate-authority-data = module.cluster.cluster_ca_certificate } }]
    contexts        = [{ name = local.cluster_name, context = { cluster = local.cluster_name, user = local.cluster_name } }]
    users = [{
      name = local.cluster_name
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "kubelogin"
          args       = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
        }
      }
    }]
  })
}

module "contract" {
  source = "../../modules/contract"

  provider_name        = "azure"
  cluster_name         = module.cluster.cluster_name
  cluster_endpoint     = module.cluster.cluster_endpoint
  kubeconfig_path      = local_file.kubeconfig.filename
  kube_context         = local.cluster_name
  storage_class        = local.platform.storage_class
  gateway_service_type = local.platform.gateway_service_type
  lb_annotations       = local.lb_annotations
  network_id           = module.network.vnet_id
  private_subnet_ids   = local.spec.network.privateSubnets ? [module.network.node_subnet_id] : []
}
