# Mocked Google provider (shared mocks in terraform/tests/mocks/gcp): no
# credentials, no API calls, no cost.

mock_provider "google" {
  source = "../../../tests/mocks/gcp"
}

variables {
  name        = "golden-test"
  region      = "us-central1"
  cidr        = "10.20.0.0/16"
  zone_count  = 3
  nat_gateway = "single"
}

run "three_zones_single_nat" {
  assert {
    condition     = jsonencode(output.zones) == jsonencode(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "expected the first 3 zones in name order"
  }
  assert {
    condition     = output.ranges.nodes == "10.20.0.0/20" && output.ranges.services == "10.20.16.0/20" && output.ranges.pods == "10.20.128.0/17"
    error_message = "unexpected node/service/pod ranges"
  }
  assert {
    condition = (
      google_compute_subnetwork.nodes.secondary_ip_range[0].range_name == "pods" &&
      google_compute_subnetwork.nodes.secondary_ip_range[0].ip_cidr_range == "10.20.128.0/17" &&
      google_compute_subnetwork.nodes.secondary_ip_range[1].range_name == "services"
    )
    error_message = "the node subnet needs pods and services secondary ranges"
  }
  assert {
    condition     = google_compute_subnetwork.nodes.private_ip_google_access
    error_message = "private nodes need Private Google Access"
  }
  assert {
    condition     = output.nat.gateways == 1 && output.nat.static_ips == 0 && output.nat.ip_allocation == "AUTO_ONLY"
    error_message = "natGateway single: one Cloud NAT with auto-allocated addresses"
  }
  assert {
    condition     = !google_compute_network.this.auto_create_subnetworks
    error_message = "the VPC must be custom mode"
  }
}

run "nat_per_zone" {
  variables {
    zone_count  = 2
    nat_gateway = "perZone"
  }

  assert {
    condition     = output.nat.gateways == 1 && output.nat.static_ips == 2 && output.nat.ip_allocation == "MANUAL_ONLY"
    error_message = "natGateway perZone: one Cloud NAT with one static address per zone"
  }
  assert {
    condition     = length(google_compute_router_nat.this[0].nat_ips) == 2
    error_message = "the NAT should use the static addresses"
  }
}

run "no_nat" {
  variables {
    zone_count  = 1
    nat_gateway = "none"
  }

  assert {
    condition     = output.nat.gateways == 0 && length(google_compute_router.this) == 0
    error_message = "natGateway none: no router, no NAT"
  }
  assert {
    condition     = length(output.zones) == 1
    error_message = "zone_count 1 should use one zone"
  }
}

run "smallest_network" {
  variables { cidr = "10.30.0.0/20" }

  assert {
    condition     = output.ranges.nodes == "10.30.0.0/24" && output.ranges.services == "10.30.1.0/24" && output.ranges.pods == "10.30.8.0/21"
    error_message = "a /20 should give a /24 for nodes and services and a /21 for pods"
  }
}

run "too_large_cidr" {
  command = plan
  variables { cidr = "10.0.0.0/8" }
  expect_failures = [var.cidr]
}
