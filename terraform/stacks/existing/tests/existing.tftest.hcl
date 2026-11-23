# No providers and no cluster: the stack only reads the config and a
# kubeconfig. Fixtures come from terraform/tests/fixtures/*.yaml, normalized
# into build/test-fixtures/ by scripts/test-terraform.sh; tests/kubeconfig.yaml
# is a fake kubeconfig with endpoints only.

variables {
  build_dir       = "/tmp/golden-k8-test"
  kubeconfig_path = "tests/kubeconfig.yaml"
}

run "orbstack" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/existing-orbstack.json" }

  assert {
    condition = (
      output.contract.provider == "existing" &&
      output.contract.cluster_name == "golden-test" &&
      output.contract.kube_context == "orbstack" &&
      output.contract.cluster_endpoint == "https://127.0.0.1:26443"
    )
    error_message = "contract should describe the orbstack context from the kubeconfig"
  }
  assert {
    condition     = startswith(output.contract.kubeconfig_path, "/") && endswith(output.contract.kubeconfig_path, "/tests/kubeconfig.yaml")
    error_message = "kubeconfig_path should be made absolute"
  }
  assert {
    condition     = output.contract.storage_class == "" && output.contract.gateway_service_type == "LoadBalancer" && output.contract.gateway_node_port == null
    error_message = "defaults: cluster's default StorageClass and a LoadBalancer gateway"
  }
}

run "contract_parity" {
  module { source = "../../tests/parity" }
  variables { contract = run.orbstack.contract }
}

run "docker_desktop_is_local" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/existing-docker-desktop.json" }

  assert {
    condition     = output.contract.cluster_endpoint == "https://kubernetes.docker.internal:6443"
    error_message = "kubernetes.docker.internal counts as a local endpoint"
  }
}

run "overrides" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/existing-overrides.json" }

  assert {
    condition = (
      output.contract.storage_class == "standard" &&
      output.contract.gateway_service_type == "NodePort" &&
      output.contract.gateway_node_port == 30080
    )
    error_message = "storageClass and providerOverrides.gatewayServiceType should reach the contract"
  }
  assert {
    condition     = output.app_url == "http://hello.localtest.me:8081"
    error_message = "app_url should use providerOverrides.hostHttpPort"
  }
}

run "rejects_context_not_allowed" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/existing-not-allowed.json" }
  expect_failures = [output.contract]
}

run "rejects_remote_endpoint" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/existing-remote.json" }
  expect_failures = [output.contract]
}

run "rejects_missing_context" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/existing-missing-context.json" }
  expect_failures = [output.contract]
}

run "rejects_other_providers" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/local-default.json" }
  expect_failures = [output.contract]
}
