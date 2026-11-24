# The outputs contract. Every stack passes its values
# through this module and outputs module.contract.contract, so all providers
# expose an identical, validated shape to the layers above the cluster.

variable "provider_name" {
  description = "Adapter that produced this contract."
  type        = string
  validation {
    condition     = contains(["local", "existing", "aws", "gcp", "azure"], var.provider_name)
    error_message = "provider_name must be one of: local, existing, aws, gcp, azure."
  }
}

variable "cluster_name" {
  description = "Cluster name."
  type        = string
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "cluster_endpoint" {
  description = "Kubernetes API server URL."
  type        = string
  validation {
    condition     = startswith(var.cluster_endpoint, "https://")
    error_message = "cluster_endpoint must be an https:// URL."
  }
}

variable "kubeconfig_path" {
  description = "Absolute path to a kubeconfig file for this cluster."
  type        = string
  validation {
    condition     = startswith(var.kubeconfig_path, "/")
    error_message = "kubeconfig_path must be an absolute path."
  }
}

variable "kube_context" {
  description = "Context name inside kubeconfig_path."
  type        = string
  validation {
    condition     = length(var.kube_context) > 0
    error_message = "kube_context must not be empty."
  }
}

variable "storage_class" {
  description = "StorageClass for PVCs. Empty string means the cluster's default StorageClass."
  type        = string
  default     = ""
}

variable "gateway_service_type" {
  description = "How the Envoy Gateway proxy Service is exposed."
  type        = string
  validation {
    condition     = contains(["NodePort", "LoadBalancer"], var.gateway_service_type)
    error_message = "gateway_service_type must be NodePort or LoadBalancer."
  }
}

variable "gateway_node_port" {
  description = "Fixed NodePort for the gateway proxy. Required for NodePort, must be null for LoadBalancer."
  type        = number
  default     = null
  validation {
    condition = (
      var.gateway_service_type == "NodePort"
      ? var.gateway_node_port != null && try(var.gateway_node_port >= 30000 && var.gateway_node_port <= 32767, false)
      : var.gateway_node_port == null
    )
    error_message = "gateway_node_port must be 30000-32767 when gateway_service_type is NodePort, and null for LoadBalancer."
  }
}

variable "lb_annotations" {
  description = "Annotations for the gateway's LoadBalancer Service (provider specific)."
  type        = map(string)
  default     = {}
}

variable "network_id" {
  description = "VPC/VNet ID. Empty for local and existing."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs. Empty for local and existing."
  type        = list(string)
  default     = []
}
