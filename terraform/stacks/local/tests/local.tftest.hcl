# Plan/apply against a mocked kind provider: no Docker needed.
# Fixtures come from terraform/tests/fixtures/*.yaml, normalized into
# build/test-fixtures/ by scripts/test-terraform.sh.

mock_provider "kind" {
  mock_resource "kind_cluster" {
    defaults = {
      endpoint     = "https://127.0.0.1:6443"
      context_name = "kind-golden-test"
    }
  }
}

variables {
  build_dir = "/tmp/golden-k8-test"
}

run "default_single_node" {
  variables { config_path = "../../../build/test-fixtures/local-default.json" }

  assert {
    condition     = kind_cluster.this.name == "golden-test"
    error_message = "cluster name should be golden-<metadata.name>"
  }
  assert {
    condition     = length(kind_cluster.this.kind_config[0].node) == 1 && kind_cluster.this.kind_config[0].node[0].role == "control-plane"
    error_message = "default local cluster should be a single control-plane node"
  }
  assert {
    condition     = startswith(kind_cluster.this.node_image, "kindest/node:v1.36.4@sha256:")
    error_message = "default version 1.36 should use the pinned v1.36.4 image"
  }
  assert {
    condition = (
      kind_cluster.this.kind_config[0].node[0].extra_port_mappings[0].container_port == 30080 &&
      kind_cluster.this.kind_config[0].node[0].extra_port_mappings[0].host_port == 80 &&
      kind_cluster.this.kind_config[0].node[0].extra_port_mappings[0].listen_address == "127.0.0.1"
    )
    error_message = "gateway NodePort 30080 should map to 127.0.0.1:80"
  }
  assert {
    condition     = kind_cluster.this.kind_config[0].networking[0].api_server_address == "127.0.0.1"
    error_message = "API server must only listen on localhost"
  }
  assert {
    condition     = output.app_url == "http://hello.localtest.me"
    error_message = "unexpected app_url"
  }
}

run "contract" {
  variables { config_path = "../../../build/test-fixtures/local-default.json" }

  assert {
    condition = (
      output.contract.contract_version == "v1" &&
      output.contract.provider == "local" &&
      output.contract.cluster_name == "golden-test" &&
      output.contract.cluster_endpoint == "https://127.0.0.1:6443" &&
      output.contract.kubeconfig_path == "/tmp/golden-k8-test/kubeconfig-golden-test" &&
      output.contract.kube_context == "kind-golden-test" &&
      output.contract.storage_class == "standard" &&
      output.contract.gateway_service_type == "NodePort" &&
      output.contract.gateway_node_port == 30080 &&
      output.contract.network_id == "" &&
      length(output.contract.private_subnet_ids) == 0
    )
    error_message = "local contract values are wrong"
  }
}

run "multiple_pools" {
  variables { config_path = "../../../build/test-fixtures/local-multipool.json" }

  assert {
    condition     = [for n in kind_cluster.this.kind_config[0].node : n.role] == ["control-plane", "worker", "worker"]
    error_message = "expected one control plane plus one worker per extra pool.min"
  }
  assert {
    condition     = [for n in kind_cluster.this.kind_config[0].node : n.labels["golden-k8/pool"]] == ["system", "apps", "apps"]
    error_message = "nodes should be labelled with their pool"
  }
  assert {
    condition     = length(kind_cluster.this.kind_config[0].node[1].extra_port_mappings) == 0
    error_message = "only the control plane maps the gateway port"
  }
}

run "host_port_override" {
  variables { config_path = "../../../build/test-fixtures/local-hostport.json" }

  assert {
    condition     = kind_cluster.this.kind_config[0].node[0].extra_port_mappings[0].host_port == 8080
    error_message = "providerOverrides.hostHttpPort should change the host port"
  }
  assert {
    condition     = output.app_url == "http://hello.localtest.me:8080"
    error_message = "app_url should include a non-default port"
  }
}

run "rejects_other_providers" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/aws-minimal.json" }
  expect_failures = [kind_cluster.this]
}

run "rejects_unpinned_version" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/local-unpinned-version.json" }
  expect_failures = [kind_cluster.this]
}

run "rejects_too_many_nodes" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/local-too-many-nodes.json" }
  expect_failures = [kind_cluster.this]
}
