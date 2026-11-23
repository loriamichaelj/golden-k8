variable "name" {
  description = "Name prefix for the VPC, subnet, router and NAT (the cluster name)."
  type        = string
}

variable "region" {
  description = "GCP region (spec.region)."
  type        = string
}

variable "cidr" {
  description = "Network IPv4 range, /16 to /20 (spec.network.cidr). Split into node, pod and service ranges."
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) >= 16 && tonumber(split("/", var.cidr)[1]) <= 20
    error_message = "cidr must be an IPv4 range from /16 to /20."
  }
}

variable "zone_count" {
  description = "Number of zones the cluster spreads nodes across (spec.network.azCount)."
  type        = number
  validation {
    condition     = var.zone_count >= 1 && var.zone_count <= 3
    error_message = "zone_count must be 1 to 3."
  }
}

variable "nat_gateway" {
  description = "Egress NAT (spec.network.natGateway): none, single (Cloud NAT, auto IPs) or perZone (Cloud NAT, one static IP per zone)."
  type        = string
  validation {
    condition     = contains(["none", "single", "perZone"], var.nat_gateway)
    error_message = "nat_gateway must be none, single or perZone."
  }
}
