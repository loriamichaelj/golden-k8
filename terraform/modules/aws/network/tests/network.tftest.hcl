# Mocked AWS provider (shared mocks in terraform/tests/mocks/aws): no
# credentials, no API calls, no cost.

mock_provider "aws" {
  source = "../../../tests/mocks/aws"
}

variables {
  name            = "golden-test"
  cidr            = "10.20.0.0/16"
  az_count        = 3
  private_subnets = true
  nat_gateway     = "single"
}

run "three_zones_single_nat" {
  assert {
    condition     = jsonencode(output.azs) == jsonencode(["us-east-1a", "us-east-1b", "us-east-1c"])
    error_message = "expected the first 3 zones in name order"
  }
  assert {
    condition     = length(output.private_subnet_ids) == 3 && length(output.public_subnet_ids) == 3
    error_message = "azCount 3 should give 3 private and 3 public subnets"
  }
  assert {
    condition     = length(output.nat_gateway_ids) == 1
    error_message = "natGateway single should give 1 NAT gateway"
  }
  assert {
    condition     = jsonencode(output.private_subnet_cidrs) == jsonencode(["10.20.0.0/18", "10.20.64.0/18", "10.20.128.0/18"])
    error_message = "private subnets should be /18s from the start of the VPC"
  }
  assert {
    condition     = jsonencode(output.public_subnet_cidrs) == jsonencode(["10.20.192.0/22", "10.20.196.0/22", "10.20.200.0/22"])
    error_message = "public subnets should be /22s in the last /18"
  }
  assert {
    condition     = jsonencode(output.node_subnet_ids) == jsonencode(output.private_subnet_ids)
    error_message = "nodes should run in the private subnets"
  }
  assert {
    condition     = module.vpc.public_subnet_objects[0].tags["kubernetes.io/role/elb"] == "1"
    error_message = "public subnets need the kubernetes.io/role/elb tag"
  }
  assert {
    condition     = module.vpc.private_subnet_objects[0].tags["kubernetes.io/role/internal-elb"] == "1"
    error_message = "private subnets need the kubernetes.io/role/internal-elb tag"
  }
}

run "nat_per_zone" {
  variables {
    az_count    = 2
    nat_gateway = "perZone"
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 2 && length(output.private_subnet_ids) == 2
    error_message = "natGateway perZone should give one NAT gateway per zone"
  }
}

run "public_only" {
  variables {
    az_count        = 1
    private_subnets = false
    nat_gateway     = "none"
  }

  assert {
    condition     = length(output.private_subnet_ids) == 0 && length(output.public_subnet_ids) == 1
    error_message = "privateSubnets false should create public subnets only"
  }
  assert {
    condition     = length(output.nat_gateway_ids) == 0
    error_message = "natGateway none should create no NAT gateway"
  }
  assert {
    condition     = jsonencode(output.node_subnet_ids) == jsonencode(output.public_subnet_ids)
    error_message = "nodes should run in the public subnets"
  }
  assert {
    condition     = module.vpc.public_subnet_objects[0].map_public_ip_on_launch
    error_message = "public node subnets must assign public IPs"
  }
}

run "smallest_vpc" {
  variables { cidr = "10.30.0.0/20" }

  assert {
    condition     = output.private_subnet_cidrs[0] == "10.30.0.0/22" && output.public_subnet_cidrs[0] == "10.30.12.0/26"
    error_message = "a /20 VPC should get /22 private and /26 public subnets"
  }
}

run "too_large_cidr" {
  command = plan
  variables { cidr = "10.0.0.0/8" }
  expect_failures = [var.cidr]
}
