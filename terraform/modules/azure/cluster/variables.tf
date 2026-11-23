variable "name" {
  description = "AKS cluster name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster (from modules/azure/network)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. \"1.36\" (spec.cluster.version); AKS picks the latest patch."
  type        = string
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36."
  }
}

variable "vnet_id" {
  description = "VNet ID; the cluster identity gets Network Contributor on it for load balancers."
  type        = string
}

variable "node_subnet_id" {
  description = "Subnet for every node pool."
  type        = string
}

variable "zones" {
  description = "Availability zones for the node pools."
  type        = list(string)
}

variable "nat_gateway" {
  description = "Whether egress goes through the subnet's NAT gateway (anything but none) or the cluster load balancer."
  type        = string
}

variable "private_nodes" {
  description = "Nodes get no public IPs (spec.network.privateSubnets)."
  type        = bool
}

variable "node_pools" {
  description = "Node pools from modules/sizing (spec.cluster.nodePools with instance_type added). The first is the AKS system pool."
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
  validation {
    condition     = length(distinct([for p in var.node_pools : substr(replace(p.name, "-", ""), 0, 12)])) == length(var.node_pools)
    error_message = "AKS node pool names are the pool names without dashes, cut to 12 characters; they must stay unique."
  }
}

variable "authorized_ip_ranges" {
  description = "Ranges allowed to reach the API server (providerOverrides.authorizedIpRanges). Empty: no restriction."
  type        = list(string)
  default     = []
}

variable "sku_tier" {
  description = "AKS control plane tier (providerOverrides.skuTier): Free, Standard or Premium."
  type        = string
  default     = "Free"
  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "tags" {
  description = "Tags for every taggable resource (azurerm has no provider-level default tags)."
  type        = map(string)
  default     = {}
}
