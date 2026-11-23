# Plan/apply against mocked providers: no Azure credentials, no API calls, no
# cost. Fixtures come from terraform/tests/fixtures/*.yaml and
# environments/*-example.yaml, normalized into build/test-fixtures/ by
# scripts/test-terraform.sh.

mock_provider "azurerm" {
  source = "../../tests/mocks/azure"
}

# The kubeconfig is not written.
mock_provider "local" {}

variables {
  build_dir = "/tmp/golden-k8-test"
}

run "defaults" {
  variables { config_path = "../../../build/test-fixtures/azure-minimal.json" }

  assert {
    condition     = output.network.resource_group == "golden-test-rg" && length(output.network.zones) == 3 && output.network.nat.gateways == 1 && output.network.nat.public_ips == 1
    error_message = "default network: resource group, 3 zones, one NAT gateway with one IP"
  }
  assert {
    condition     = jsonencode(keys(output.node_pools)) == jsonencode(["system"])
    error_message = "default cluster: one system pool"
  }
  assert {
    condition     = output.node_pools.system.vm_size == "Standard_D2s_v5" && output.node_pools.system.min == 2 && output.node_pools.system.max == 3
    error_message = "system pool: small → Standard_D2s_v5, min 2, max 3"
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
  variables { config_path = "../../../build/test-fixtures/azure-minimal.json" }

  assert {
    condition = (
      output.contract.contract_version == "v1" &&
      output.contract.provider == "azure" &&
      output.contract.cluster_name == "golden-test" &&
      output.contract.cluster_endpoint == "https://golden-test-abcd1234.hcp.eastus.azmk8s.io:443" &&
      output.contract.kubeconfig_path == "/tmp/golden-k8-test/kubeconfig-golden-test" &&
      output.contract.kube_context == "golden-test" &&
      output.contract.storage_class == "managed-csi" &&
      output.contract.gateway_service_type == "LoadBalancer" &&
      output.contract.gateway_node_port == null &&
      jsonencode(output.contract.lb_annotations) == jsonencode({ "service.beta.kubernetes.io/azure-load-balancer-health-probe-protocol" = "tcp" }) &&
      output.contract.network_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/golden-test-rg/providers/Microsoft.Network/virtualNetworks/golden-test" &&
      length(output.contract.private_subnet_ids) == 1
    )
    error_message = "azure contract values are wrong"
  }
}

run "contract_parity" {
  module { source = "../../tests/parity" }
  variables { contract = run.contract.contract }
}

run "kubeconfig_uses_kubelogin" {
  variables { config_path = "../../../build/test-fixtures/azure-minimal.json" }

  assert {
    condition = (
      yamldecode(local_file.kubeconfig.content).users[0].user.exec.command == "kubelogin" &&
      contains(yamldecode(local_file.kubeconfig.content).users[0].user.exec.args, "azurecli") &&
      yamldecode(local_file.kubeconfig.content).clusters[0].cluster.server == output.contract.cluster_endpoint &&
      local_file.kubeconfig.file_permission == "0600"
    )
    error_message = "kubeconfig should use kubelogin with the Azure CLI, with no stored credentials"
  }
}

run "tags" {
  variables { config_path = "../../../build/test-fixtures/azure-overrides.json" }

  assert {
    condition = (
      local.tags["golden-k8-environment"] == "test" &&
      local.tags["golden-k8-managed"] == "true" &&
      local.tags["golden-k8-owner"] == "platform" &&
      local.tags["team"] == "example" &&
      alltrue([for k in keys(local.tags) : !can(regex("[<>%&\\\\?/]", k))])
    )
    error_message = "tags should carry metadata.tags plus golden-k8-* keys, all valid Azure tag names"
  }
  assert {
    condition     = module.network.resource_group_name == "golden-test-rg" && module.cluster.cluster_name == "golden-test"
    error_message = "network and cluster should plan with tags"
  }
}

run "overrides" {
  variables { config_path = "../../../build/test-fixtures/azure-overrides.json" }

  assert {
    condition = jsonencode(output.contract.lb_annotations) == jsonencode({
      "service.beta.kubernetes.io/azure-load-balancer-health-probe-protocol" = "tcp"
      "service.beta.kubernetes.io/azure-load-balancer-internal"              = "true"
    })
    error_message = "providerOverrides.lbAnnotations should be merged over the platform defaults"
  }
  assert {
    condition     = output.network.nat.public_ips == 3
    error_message = "natGateway perZone: one public IP per zone"
  }
}

run "public_only" {
  variables { config_path = "../../../build/test-fixtures/azure-public-only.json" }

  assert {
    condition     = output.network.nat.gateways == 0 && length(output.network.zones) == 1 && output.network.node_subnet == "10.40.0.0/22"
    error_message = "privateSubnets false + natGateway none: one zone, no NAT, /22 node subnet"
  }
  assert {
    condition     = length(output.contract.private_subnet_ids) == 0
    error_message = "contract should list no private subnets"
  }
  assert {
    condition     = output.node_pools.system.vm_size == "Standard_D8s_v5"
    error_message = "large → Standard_D8s_v5"
  }
}

run "example" {
  variables { config_path = "../../../build/test-fixtures/env-azure-example.json" }

  assert {
    condition     = toset(keys(output.node_pools)) == toset(["system", "apps"])
    error_message = "environments/azure-example.yaml: system and apps pools"
  }
  assert {
    condition     = output.node_pools.apps.vm_size == "Standard_D4s_v5" && output.node_pools.apps.max == 5 && output.node_pools.apps.mode == "User"
    error_message = "apps pool: User mode, medium → Standard_D4s_v5, max 5"
  }
}

run "wrong_provider" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/gcp-minimal.json" }
  expect_failures = [var.config_path]
}
