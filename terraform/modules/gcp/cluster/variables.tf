variable "name" {
  description = "GKE cluster name."
  type        = string
}

variable "project_id" {
  description = "GCP project ID (for the Workload Identity pool and IAM)."
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "No GCP project: set spec.cluster.providerOverrides.project, GOOGLE_PROJECT or gcloud's default project."
  }
}

variable "region" {
  description = "GCP region; the cluster and its node pools are regional."
  type        = string
}

variable "zones" {
  description = "Zones for the nodes (from modules/gcp/network)."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. \"1.36\" (spec.cluster.version)."
  type        = string
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36."
  }
}

variable "network_id" {
  description = "VPC network ID."
  type        = string
}

variable "subnetwork_id" {
  description = "Node subnet ID."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range for pods."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range for services."
  type        = string
}

variable "private_nodes" {
  description = "Nodes get no external IPs (spec.network.privateSubnets); egress goes through Cloud NAT."
  type        = bool
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

variable "master_authorized_cidrs" {
  description = "Ranges allowed to reach the API endpoint from outside the VPC (providerOverrides.masterAuthorizedCidrs). Empty: VPC only."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "Block terraform destroy of the cluster (providerOverrides.deletionProtection)."
  type        = bool
  default     = true
}
