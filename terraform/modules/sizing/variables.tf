variable "cloud" {
  description = "Target provider whose catalog to use: local, aws, gcp or azure."
  type        = string

  validation {
    condition     = contains(["local", "aws", "gcp", "azure"], var.cloud)
    error_message = "cloud must be one of: local, aws, gcp, azure."
  }
}

variable "node_pools" {
  description = "Node pools from spec.cluster.nodePools."
  type = list(object({
    name = string
    size = string
    min  = number
    max  = number
  }))

  validation {
    condition     = alltrue([for p in var.node_pools : contains(["small", "medium", "large"], p.size)])
    error_message = "Every node pool size must be small, medium or large."
  }
}
