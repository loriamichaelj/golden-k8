# Every size × provider maps to the expected SKU.

variables {
  node_pools = [
    { name = "s", size = "small", min = 1, max = 1 },
    { name = "m", size = "medium", min = 1, max = 1 },
    { name = "l", size = "large", min = 1, max = 1 },
  ]
}

run "aws" {
  command = plan
  variables { cloud = "aws" }
  assert {
    condition     = [for p in output.node_pools : p.instance_type] == ["m7i.large", "m7i.xlarge", "m7i.2xlarge"]
    error_message = "unexpected AWS instance types"
  }
}

run "gcp" {
  command = plan
  variables { cloud = "gcp" }
  assert {
    condition     = [for p in output.node_pools : p.instance_type] == ["e2-standard-2", "e2-standard-4", "e2-standard-8"]
    error_message = "unexpected GCP machine types"
  }
}

run "azure" {
  command = plan
  variables { cloud = "azure" }
  assert {
    condition     = [for p in output.node_pools : p.instance_type] == ["Standard_D2s_v5", "Standard_D4s_v5", "Standard_D8s_v5"]
    error_message = "unexpected Azure VM sizes"
  }
}

run "local" {
  command = plan
  variables { cloud = "local" }
  assert {
    condition     = alltrue([for p in output.node_pools : p.instance_type == "kind-node"])
    error_message = "local pools should all map to kind-node"
  }
}

run "shapes_and_passthrough" {
  command = plan
  variables { cloud = "gcp" }
  assert {
    condition     = [for p in output.node_pools : [p.vcpu, p.memory_gib]] == [[2, 8], [4, 16], [8, 32]]
    error_message = "unexpected vCPU/memory shapes"
  }
  assert {
    condition     = output.node_pools[1].name == "m" && output.node_pools[1].min == 1 && output.node_pools[1].max == 1
    error_message = "pool fields must pass through unchanged"
  }
}

run "rejects_unknown_cloud" {
  command = plan
  variables { cloud = "openstack" }
  expect_failures = [var.cloud]
}

run "rejects_unknown_size" {
  command = plan
  variables {
    cloud      = "aws"
    node_pools = [{ name = "x", size = "xlarge", min = 1, max = 1 }]
  }
  expect_failures = [var.node_pools]
}
