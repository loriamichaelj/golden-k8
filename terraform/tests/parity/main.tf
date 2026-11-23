# Contract parity: every stack must emit exactly these keys with these types.
# Each stack's tests run this module against that stack's contract output:
#
#   run "contract_parity" {
#     module { source = "../../tests/parity" }
#     variables { contract = run.<earlier run>.contract }
#   }
#
# No providers and no resources: the checks are variable validations.

terraform {
  required_version = ">= 1.9, < 2.0"
}

locals {
  keys = [
    "cluster_endpoint", "cluster_name", "contract_version", "gateway_node_port", "gateway_service_type",
    "kube_context", "kubeconfig_path", "lb_annotations", "network_id", "private_subnet_ids", "provider",
    "storage_class",
  ]
}

variable "contract" {
  description = "A stack's contract output."
  type        = any

  validation {
    condition     = jsonencode(sort(keys(var.contract))) == jsonencode(local.keys)
    error_message = "The contract must have exactly the v1 keys."
  }
  validation {
    condition     = var.contract.contract_version == "v1"
    error_message = "contract_version must be v1."
  }
  validation {
    condition = alltrue([
      for k in ["provider", "cluster_name", "cluster_endpoint", "kubeconfig_path", "kube_context", "storage_class", "gateway_service_type", "network_id"] :
      can(tostring(var.contract[k])) && !can(tolist(var.contract[k])) && !can(tomap(var.contract[k]))
    ])
    error_message = "provider, cluster_name, cluster_endpoint, kubeconfig_path, kube_context, storage_class, gateway_service_type and network_id must be strings."
  }
  validation {
    condition     = var.contract.gateway_node_port == null || can(tonumber(var.contract.gateway_node_port))
    error_message = "gateway_node_port must be a number or null."
  }
  validation {
    condition     = can(tomap(var.contract.lb_annotations)) && alltrue([for v in values(var.contract.lb_annotations) : can(tostring(v))])
    error_message = "lb_annotations must be a map of strings."
  }
  validation {
    condition     = can(tolist(var.contract.private_subnet_ids)) && alltrue([for v in var.contract.private_subnet_ids : can(tostring(v))])
    error_message = "private_subnet_ids must be a list of strings."
  }
}

output "contract" {
  description = "The contract, unchanged, once every check has passed."
  value       = var.contract
}
