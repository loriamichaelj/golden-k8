variable "name" {
  description = "Name prefix for the resource group, VNet, subnet and NAT gateway (the cluster name)."
  type        = string
}

variable "location" {
  description = "Azure region (spec.region)."
  type        = string
}

variable "cidr" {
  description = "VNet IPv4 range, /16 to /20 (spec.network.cidr). Pods and services use overlay ranges outside it."
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) >= 16 && tonumber(split("/", var.cidr)[1]) <= 20
    error_message = "cidr must be an IPv4 range from /16 to /20."
  }
  validation {
    # The cluster's pod (192.168.0.0/16) and service (172.16.0.0/16) ranges
    # must not overlap the VNet. A /16-/20 sits inside one of them exactly when
    # its first two octets match.
    condition     = !contains(["192.168", "172.16"], join(".", slice(split(".", var.cidr), 0, 2)))
    error_message = "cidr must not overlap the AKS pod range 192.168.0.0/16 or service range 172.16.0.0/16."
  }
}

variable "nat_gateway" {
  description = "Egress NAT (spec.network.natGateway): none, single (one public IP) or perZone (one public IP per zone)."
  type        = string
  validation {
    condition     = contains(["none", "single", "perZone"], var.nat_gateway)
    error_message = "nat_gateway must be none, single or perZone."
  }
}

variable "zone_count" {
  description = "Number of availability zones in use (spec.network.azCount); sets the public IP count for perZone."
  type        = number
  validation {
    condition     = var.zone_count >= 1 && var.zone_count <= 3
    error_message = "zone_count must be 1 to 3."
  }
}

variable "tags" {
  description = "Tags for every taggable resource (azurerm has no provider-level default tags)."
  type        = map(string)
  default     = {}
}
