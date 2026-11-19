# provider: local — a kind cluster on the local Docker engine.

locals {
  config = jsondecode(file(var.config_path))
  spec   = local.config.spec

  cluster_name = "golden-${local.config.metadata.name}"

  # Envoy Gateway's proxy Service uses this fixed NodePort; kind maps it to
  # the host (127.0.0.1 only) so the app is reachable at http://<host>:<port>.
  gateway_node_port = 30080
  host_http_port    = try(local.spec.cluster.providerOverrides.hostHttpPort, 80)

  # kind v0.33.0 node images, pinned by digest.
  node_images = {
    "1.34" = "kindest/node:v1.34.11@sha256:44e222ee2132dab25ff87301682f89eb82c7880ea3a1bf543bfe9708fd08d67d"
    "1.35" = "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0"
    "1.36" = "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
    "1.37" = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"
  }

  # One kind node per pool.min (kind has no autoscaler). The first node is the
  # control plane; the rest are workers. Every node is labelled with its pool.
  nodes = flatten([
    for p in module.sizing.node_pools : [for i in range(p.min) : { pool = p.name }]
  ])
}

module "sizing" {
  source     = "../../modules/sizing"
  cloud      = "local"
  node_pools = local.spec.cluster.nodePools
}

resource "kind_cluster" "this" {
  name            = local.cluster_name
  node_image      = lookup(local.node_images, local.spec.cluster.version, null)
  kubeconfig_path = "${var.build_dir}/kubeconfig-${local.cluster_name}"
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = "127.0.0.1"
    }

    dynamic "node" {
      for_each = local.nodes
      content {
        role   = node.key == 0 ? "control-plane" : "worker"
        labels = { "golden-k8/pool" = node.value.pool }

        dynamic "extra_port_mappings" {
          for_each = node.key == 0 ? [1] : []
          content {
            container_port = local.gateway_node_port
            host_port      = local.host_http_port
            listen_address = "127.0.0.1"
            protocol       = "TCP"
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.spec.provider == "local"
      error_message = "stacks/local only handles provider local (got ${local.spec.provider})."
    }
    precondition {
      condition     = contains(keys(local.node_images), local.spec.cluster.version)
      error_message = "Kubernetes ${local.spec.cluster.version} has no pinned kind node image. Supported: ${join(", ", keys(local.node_images))}."
    }
    precondition {
      condition     = length(local.nodes) <= 4
      error_message = "Local clusters are limited to 4 nodes (sum of nodePools[].min); got ${length(local.nodes)}."
    }
  }
}

module "contract" {
  source = "../../modules/contract"

  provider_name        = "local"
  cluster_name         = kind_cluster.this.name
  cluster_endpoint     = kind_cluster.this.endpoint
  kubeconfig_path      = kind_cluster.this.kubeconfig_path
  kube_context         = kind_cluster.this.context_name
  storage_class        = "standard" # kind's bundled local-path provisioner
  gateway_service_type = "NodePort"
  gateway_node_port    = local.gateway_node_port
}
