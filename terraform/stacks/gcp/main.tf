# provider: gcp — a VPC and a regional GKE cluster. Validated and mock-tested
# only: golden-k8 never provisions cloud resources (spec.pipeline.apply stays
# false).

locals {
  config   = jsondecode(file(var.config_path))
  spec     = local.config.spec
  platform = yamldecode(file("${path.module}/platform.yaml"))

  cluster_name = "golden-${local.config.metadata.name}"
  overrides    = try(local.spec.cluster.providerOverrides, {})

  # The project comes from providerOverrides.project, else from the provider's
  # environment (GOOGLE_PROJECT, gcloud's default project).
  project = data.google_client_config.current.project

  # Labelled on every resource through the provider's default_labels. GCP
  # label keys allow no "/", hence golden-k8-*.
  labels = merge(local.config.metadata.tags, {
    "golden-k8-environment" = local.config.metadata.name
    "golden-k8-owner"       = local.config.metadata.owner
    "golden-k8-managed"     = "true"
  })

  lb_annotations = merge(local.platform.lb_annotations, try(local.overrides.lbAnnotations, {}))
  kube_context   = "gke_${local.project}_${local.spec.region}_${local.cluster_name}"
}

provider "google" {
  project        = try(local.overrides.project, null)
  region         = local.spec.region
  default_labels = local.labels
}

data "google_client_config" "current" {}

module "sizing" {
  source     = "../../modules/sizing"
  cloud      = "gcp"
  node_pools = local.spec.cluster.nodePools
}

module "network" {
  source = "../../modules/gcp/network"

  name        = local.cluster_name
  region      = local.spec.region
  cidr        = local.spec.network.cidr
  zone_count  = local.spec.network.azCount
  nat_gateway = local.spec.network.natGateway
}

module "cluster" {
  source = "../../modules/gcp/cluster"

  name                    = local.cluster_name
  project_id              = local.project
  region                  = local.spec.region
  zones                   = module.network.zones
  kubernetes_version      = local.spec.cluster.version
  network_id              = module.network.network_id
  subnetwork_id           = module.network.subnetwork_id
  pods_range_name         = module.network.pods_range_name
  services_range_name     = module.network.services_range_name
  private_nodes           = local.spec.network.privateSubnets
  node_pools              = module.sizing.node_pools
  master_authorized_cidrs = try(local.overrides.masterAuthorizedCidrs, [])
  deletion_protection     = try(local.overrides.deletionProtection, true)
}

# Exec-based kubeconfig: no credentials in the file, tokens come from
# gke-gcloud-auth-plugin (gcloud components install gke-gcloud-auth-plugin).
resource "local_file" "kubeconfig" {
  filename        = "${var.build_dir}/kubeconfig-${local.cluster_name}"
  file_permission = "0600"
  content = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = local.kube_context
    clusters        = [{ name = local.kube_context, cluster = { server = module.cluster.cluster_endpoint, certificate-authority-data = module.cluster.cluster_ca_certificate } }]
    contexts        = [{ name = local.kube_context, context = { cluster = local.kube_context, user = local.kube_context } }]
    users = [{
      name = local.kube_context
      user = {
        exec = {
          apiVersion         = "client.authentication.k8s.io/v1beta1"
          command            = "gke-gcloud-auth-plugin"
          provideClusterInfo = true
          installHint        = "Install gke-gcloud-auth-plugin: gcloud components install gke-gcloud-auth-plugin"
        }
      }
    }]
  })
}

module "contract" {
  source = "../../modules/contract"

  provider_name        = "gcp"
  cluster_name         = module.cluster.cluster_name
  cluster_endpoint     = module.cluster.cluster_endpoint
  kubeconfig_path      = local_file.kubeconfig.filename
  kube_context         = local.kube_context
  storage_class        = local.platform.storage_class
  gateway_service_type = local.platform.gateway_service_type
  lb_annotations       = local.lb_annotations
  network_id           = module.network.network_id
  private_subnet_ids   = local.spec.network.privateSubnets ? [module.network.subnetwork_id] : []
}
