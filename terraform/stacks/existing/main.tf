# provider: existing — a cluster golden-k8 did not create.
#
# Creates no resources and contacts no cluster. scripts/infra.sh snapshots the
# one context named in spec.cluster.existing.context into a dedicated
# kubeconfig; this stack reads it and emits the outputs contract, refusing
# (output preconditions) anything that is not an allowed, local cluster.

locals {
  config = jsondecode(file(var.config_path))
  spec   = local.config.spec
  # Fallback only so a wrong provider reaches the precondition that names it.
  existing = try(local.spec.cluster.existing, { context = "(none)", allowedContexts = [] })

  cluster_name    = "golden-${local.config.metadata.name}"
  kubeconfig_path = abspath(coalesce(var.kubeconfig_path, "${var.build_dir}/kubeconfig-${local.cluster_name}"))
  kubeconfig      = yamldecode(file(local.kubeconfig_path))

  context = local.existing.context
  context_entry = one([
    for c in try(local.kubeconfig.contexts, []) : c.context if c.name == local.context
  ])
  # A sentinel when the context is missing, so the output preconditions (not
  # the contract module's URL check) report the real problem.
  server = try(one([
    for c in try(local.kubeconfig.clusters, []) : c.cluster.server if c.name == local.context_entry.cluster
  ]), "https://context-not-found.invalid")

  # allowedContexts are globs (only * and ? are special).
  allowed_patterns = [
    for p in local.existing.allowedContexts :
    "^${replace(replace(replace(p, ".", "\\."), "*", ".*"), "?", ".")}$"
  ]
  context_allowed = anytrue([for r in local.allowed_patterns : can(regex(r, local.context))])

  # Only clusters on this machine: loopback, OrbStack and Docker Desktop names.
  server_host  = try(regex("^https://(\\[[^\\]]+\\]|[^/:]+)", local.server)[0], "")
  server_local = contains(["127.0.0.1", "localhost", "[::1]", "kubernetes.docker.internal"], local.server_host) || endswith(local.server_host, ".orb.local")

  overrides            = local.spec.cluster.providerOverrides
  gateway_service_type = try(local.overrides.gatewayServiceType, "LoadBalancer")
}

module "contract" {
  source = "../../modules/contract"

  provider_name        = "existing"
  cluster_name         = local.cluster_name
  cluster_endpoint     = local.server
  kubeconfig_path      = local.kubeconfig_path
  kube_context         = local.context
  storage_class        = try(local.existing.storageClass, "")
  gateway_service_type = local.gateway_service_type
  gateway_node_port    = local.gateway_service_type == "NodePort" ? try(local.overrides.gatewayNodePort, 30080) : null
}
