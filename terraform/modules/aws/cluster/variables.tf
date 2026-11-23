variable "name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. \"1.36\" (spec.cluster.version)."
  type        = string
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36."
  }
}

variable "vpc_id" {
  description = "VPC for the cluster security groups."
  type        = string
}

variable "node_subnet_ids" {
  description = "Subnets for the nodes and the control plane network interfaces."
  type        = list(string)
}

variable "node_pools" {
  description = "Node pools from modules/sizing (spec.cluster.nodePools with instance_type added)."
  type = list(object({
    name          = string
    size          = string
    min           = number
    max           = number
    instance_type = string
  }))
  validation {
    condition     = length(var.node_pools) > 0 && alltrue([for p in var.node_pools : p.min <= p.max])
    error_message = "At least one node pool is required, and every pool needs min <= max."
  }
}

variable "endpoint_public_access_cidrs" {
  description = "Ranges allowed to reach the public API endpoint (providerOverrides.endpointPublicAccessCidrs)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Extra tags for every resource (the provider's default_tags already carry the environment tags)."
  type        = map(string)
  default     = {}
}
