output "contract" {
  description = "Outputs contract (see modules/contract)."
  value       = module.contract.contract

  precondition {
    condition     = local.spec.provider == "existing"
    error_message = "stacks/existing only handles provider existing (got ${local.spec.provider})."
  }
  precondition {
    condition     = local.context_entry != null
    error_message = "Context ${local.context} is not in ${local.kubeconfig_path}."
  }
  precondition {
    condition     = local.context_allowed
    error_message = "Context ${local.context} does not match spec.cluster.existing.allowedContexts (${join(", ", local.existing.allowedContexts)})."
  }
  precondition {
    condition     = local.server_local
    error_message = "Context ${local.context} points at ${local.server}: golden-k8 only installs onto clusters on this machine (127.0.0.1, localhost, *.orb.local, kubernetes.docker.internal)."
  }
}

output "app_url" {
  description = "Where the sample app will be reachable once deployed (gateway exposed on localhost)."
  value       = "http://${local.spec.app.expose.host}${try(local.overrides.hostHttpPort, 80) == 80 ? "" : ":${local.overrides.hostHttpPort}"}"
}
