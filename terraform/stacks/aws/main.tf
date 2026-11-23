# provider: aws — a VPC and an EKS cluster. Validated and mock-tested only:
# golden-k8 never provisions cloud resources (spec.pipeline.apply stays false).

locals {
  config   = jsondecode(file(var.config_path))
  spec     = local.config.spec
  platform = yamldecode(file("${path.module}/platform.yaml"))

  cluster_name = "golden-${local.config.metadata.name}"
  overrides    = try(local.spec.cluster.providerOverrides, {})

  # Tagged on every resource through the provider's default_tags.
  tags = merge(local.config.metadata.tags, {
    "golden-k8/environment" = local.config.metadata.name
    "golden-k8/owner"       = local.config.metadata.owner
    "golden-k8/managed"     = "true"
  })

  lb_annotations = merge(local.platform.lb_annotations, try(local.overrides.lbAnnotations, {}))
}

provider "aws" {
  region = local.spec.region

  default_tags {
    tags = local.tags
  }
}

module "sizing" {
  source     = "../../modules/sizing"
  cloud      = "aws"
  node_pools = local.spec.cluster.nodePools
}

module "network" {
  source = "../../modules/aws/network"

  name            = local.cluster_name
  cidr            = local.spec.network.cidr
  az_count        = local.spec.network.azCount
  private_subnets = local.spec.network.privateSubnets
  nat_gateway     = local.spec.network.natGateway
}

module "cluster" {
  source = "../../modules/aws/cluster"

  name                         = local.cluster_name
  kubernetes_version           = local.spec.cluster.version
  vpc_id                       = module.network.vpc_id
  node_subnet_ids              = module.network.node_subnet_ids
  node_pools                   = module.sizing.node_pools
  endpoint_public_access_cidrs = try(local.overrides.endpointPublicAccessCidrs, ["0.0.0.0/0"])
}

# Exec-based kubeconfig: no credentials in the file, tokens come from the AWS CLI.
resource "local_file" "kubeconfig" {
  filename        = "${var.build_dir}/kubeconfig-${local.cluster_name}"
  file_permission = "0600"
  content = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = module.cluster.cluster_arn
    clusters        = [{ name = module.cluster.cluster_arn, cluster = { server = module.cluster.cluster_endpoint, certificate-authority-data = module.cluster.cluster_certificate_authority_data } }]
    contexts        = [{ name = module.cluster.cluster_arn, context = { cluster = module.cluster.cluster_arn, user = module.cluster.cluster_arn } }]
    users = [{
      name = module.cluster.cluster_arn
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args       = ["--region", local.spec.region, "eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--output", "json"]
        }
      }
    }]
  })
}

module "contract" {
  source = "../../modules/contract"

  provider_name        = "aws"
  cluster_name         = module.cluster.cluster_name
  cluster_endpoint     = module.cluster.cluster_endpoint
  kubeconfig_path      = local_file.kubeconfig.filename
  kube_context         = module.cluster.cluster_arn
  storage_class        = local.platform.storage_class
  gateway_service_type = local.platform.gateway_service_type
  lb_annotations       = local.lb_annotations
  network_id           = module.network.vpc_id
  private_subnet_ids   = module.network.private_subnet_ids
}
