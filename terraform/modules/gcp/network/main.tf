# GCP network: a custom-mode VPC with one regional subnet for the nodes and
# two secondary ranges (pods, services) for a VPC-native GKE cluster, plus
# Cloud NAT for egress from private nodes.
#
# Address plan, for a /16 (scales down to /20):
#   pods      cidrsubnet(cidr, 1, 1)  /17  secondary range
#   nodes     cidrsubnet(cidr, 4, 0)  /20  primary range
#   services  cidrsubnet(cidr, 4, 1)  /20  secondary range
#
# Cloud NAT is regional (it already serves every zone). natGateway single uses
# automatically allocated addresses; perZone reserves one static address per
# zone, so egress IPs are fixed and scale with the zones in use.

data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}

locals {
  zones = slice(sort(data.google_compute_zones.available.names), 0, var.zone_count)

  nodes_cidr    = cidrsubnet(var.cidr, 4, 0)
  services_cidr = cidrsubnet(var.cidr, 4, 1)
  pods_cidr     = cidrsubnet(var.cidr, 1, 1)

  pods_range_name     = "pods"
  services_range_name = "services"
}

resource "google_compute_network" "this" {
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "nodes" {
  name                     = "${var.name}-nodes"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = local.nodes_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = local.pods_cidr
  }

  secondary_ip_range {
    range_name    = local.services_range_name
    ip_cidr_range = local.services_cidr
  }
}

resource "google_compute_router" "this" {
  count = var.nat_gateway == "none" ? 0 : 1

  name    = var.name
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_address" "nat" {
  count = var.nat_gateway == "perZone" ? var.zone_count : 0

  name   = "${var.name}-nat-${count.index}"
  region = var.region
}

resource "google_compute_router_nat" "this" {
  count = var.nat_gateway == "none" ? 0 : 1

  name                               = var.name
  region                             = var.region
  router                             = google_compute_router.this[0].name
  nat_ip_allocate_option             = var.nat_gateway == "perZone" ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_ips                            = google_compute_address.nat[*].self_link
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

check "zones" {
  assert {
    condition     = length(local.zones) == var.zone_count
    error_message = "The region has fewer than ${var.zone_count} zones up."
  }
}
