variable "name" {
  description = "Name prefix for the VPC and its subnets (the cluster name)."
  type        = string
}

variable "cidr" {
  description = "VPC IPv4 range, /16 to /20 (spec.network.cidr)."
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) >= 16 && tonumber(split("/", var.cidr)[1]) <= 20
    error_message = "cidr must be an IPv4 range from /16 to /20."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (spec.network.azCount)."
  type        = number
  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be 1 to 3."
  }
}

variable "private_subnets" {
  description = "Run nodes in private subnets behind NAT (spec.network.privateSubnets)."
  type        = bool
}

variable "nat_gateway" {
  description = "NAT layout (spec.network.natGateway): none, single or perZone."
  type        = string
  validation {
    condition     = contains(["none", "single", "perZone"], var.nat_gateway)
    error_message = "nat_gateway must be none, single or perZone."
  }
}

variable "tags" {
  description = "Extra tags for every resource (the provider's default_tags already carry the environment tags)."
  type        = map(string)
  default     = {}
}
