# Plan/apply against mocked providers: no GCP credentials, no API calls, no
# cost. Fixtures come from terraform/tests/fixtures/*.yaml and
# environments/*-example.yaml, normalized into build/test-fixtures/ by
# scripts/test-terraform.sh.

mock_provider "google" {
  source = "../../tests/mocks/gcp"
}

# The kubeconfig is not written.
mock_provider "local" {}

variables {
  build_dir = "/tmp/golden-k8-test"
}

run "defaults" {
  variables { config_path = "../../../build/test-fixtures/gcp-minimal.json" }

  assert {
    condition     = length(output.network.zones) == 3 && output.network.nat.gateways == 1 && output.network.nat.ip_allocation == "AUTO_ONLY"
    error_message = "default network: 3 zones, one Cloud NAT with auto IPs"
  }
  assert {
    condition     = jsonencode(keys(output.node_pools)) == jsonencode(["system"])
    error_message = "default cluster: one system pool"
  }
  assert {
    condition     = output.node_pools.system.machine_type == "e2-standard-2" && output.node_pools.system.total_min == 2 && output.node_pools.system.total_max == 3
    error_message = "system pool: small → e2-standard-2, min 2, max 3"
  }
  assert {
    condition     = module.cluster.cluster_name == "golden-test"
    error_message = "cluster name should be golden-<metadata.name>"
  }
  assert {
    condition     = output.app_url == "http://hello.example.com"
    error_message = "unexpected app_url"
  }
}

run "contract" {
  variables { config_path = "../../../build/test-fixtures/gcp-minimal.json" }

  assert {
    condition = (
      output.contract.contract_version == "v1" &&
      output.contract.provider == "gcp" &&
      output.contract.cluster_name == "golden-test" &&
      output.contract.cluster_endpoint == "https://203.0.113.10" &&
      output.contract.kubeconfig_path == "/tmp/golden-k8-test/kubeconfig-golden-test" &&
      output.contract.kube_context == "gke_example-project_us-central1_golden-test" &&
      output.contract.storage_class == "standard-rwo" &&
      output.contract.gateway_service_type == "LoadBalancer" &&
      output.contract.gateway_node_port == null &&
      jsonencode(output.contract.lb_annotations) == jsonencode({ "cloud.google.com/l4-rbs" = "enabled" }) &&
      output.contract.network_id == "projects/example-project/global/networks/golden-test" &&
      jsonencode(output.contract.private_subnet_ids) == jsonencode(["projects/example-project/regions/us-central1/subnetworks/golden-test-nodes"])
    )
    error_message = "gcp contract values are wrong"
  }
}

run "contract_parity" {
  module { source = "../../tests/parity" }
  variables { contract = run.contract.contract }
}

run "kubeconfig_uses_gke_auth_plugin" {
  variables { config_path = "../../../build/test-fixtures/gcp-minimal.json" }

  assert {
    condition = (
      yamldecode(local_file.kubeconfig.content).users[0].user.exec.command == "gke-gcloud-auth-plugin" &&
      yamldecode(local_file.kubeconfig.content).current-context == "gke_example-project_us-central1_golden-test" &&
      yamldecode(local_file.kubeconfig.content).clusters[0].cluster.server == output.contract.cluster_endpoint &&
      local_file.kubeconfig.file_permission == "0600"
    )
    error_message = "kubeconfig should use gke-gcloud-auth-plugin, with no stored credentials"
  }
}

run "labels" {
  variables { config_path = "../../../build/test-fixtures/gcp-overrides.json" }

  assert {
    condition = (
      local.labels["golden-k8-environment"] == "test" &&
      local.labels["golden-k8-managed"] == "true" &&
      local.labels["golden-k8-owner"] == "platform" &&
      local.labels["team"] == "example" &&
      alltrue([for k in keys(local.labels) : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    )
    error_message = "default_labels should carry metadata.tags plus golden-k8-* keys, all valid GCP label keys"
  }
}

run "overrides" {
  variables { config_path = "../../../build/test-fixtures/gcp-overrides.json" }

  assert {
    condition = jsonencode(output.contract.lb_annotations) == jsonencode({
      "cloud.google.com/l4-rbs"              = "enabled"
      "networking.gke.io/load-balancer-type" = "Internal"
    })
    error_message = "providerOverrides.lbAnnotations should be merged over the platform defaults"
  }
  assert {
    condition     = output.network.nat.static_ips == 3 && output.network.nat.ip_allocation == "MANUAL_ONLY"
    error_message = "natGateway perZone: one static NAT address per zone"
  }
}

run "public_only" {
  variables { config_path = "../../../build/test-fixtures/gcp-public-only.json" }

  assert {
    condition     = output.network.nat.gateways == 0 && length(output.network.zones) == 1
    error_message = "privateSubnets false + natGateway none: one zone, no NAT"
  }
  assert {
    condition     = length(output.contract.private_subnet_ids) == 0
    error_message = "contract should list no private subnets"
  }
  assert {
    condition     = output.node_pools.system.machine_type == "e2-standard-8"
    error_message = "large → e2-standard-8"
  }
}

run "example" {
  variables { config_path = "../../../build/test-fixtures/env-gcp-example.json" }

  assert {
    condition     = toset(keys(output.node_pools)) == toset(["system", "apps"])
    error_message = "environments/gcp-example.yaml: system and apps pools"
  }
  assert {
    condition     = output.node_pools.apps.machine_type == "e2-standard-4" && output.node_pools.apps.total_max == 5
    error_message = "apps pool: medium → e2-standard-4, max 5"
  }
}

run "wrong_provider" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/aws-minimal.json" }
  expect_failures = [var.config_path]
}
