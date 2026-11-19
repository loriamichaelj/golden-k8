variables {
  provider_name        = "local"
  cluster_name         = "golden-test"
  cluster_endpoint     = "https://127.0.0.1:6443"
  kubeconfig_path      = "/tmp/golden/kubeconfig"
  kube_context         = "kind-golden-test"
  gateway_service_type = "NodePort"
  gateway_node_port    = 30080
}

run "shape" {
  command = plan
  assert {
    condition = toset(keys(output.contract)) == toset([
      "contract_version", "provider", "cluster_name", "cluster_endpoint", "kubeconfig_path",
      "kube_context", "storage_class", "gateway_service_type", "gateway_node_port",
      "lb_annotations", "network_id", "private_subnet_ids",
    ])
    error_message = "contract keys changed: update every stack, Ansible and contract_version"
  }
  assert {
    condition     = output.contract.contract_version == "v1"
    error_message = "unexpected contract_version"
  }
}

run "defaults_for_local" {
  command = plan
  assert {
    condition     = output.contract.storage_class == "" && output.contract.network_id == "" && length(output.contract.private_subnet_ids) == 0 && length(output.contract.lb_annotations) == 0
    error_message = "optional fields should default to empty"
  }
}

run "load_balancer" {
  command = plan
  variables {
    provider_name        = "aws"
    gateway_service_type = "LoadBalancer"
    gateway_node_port    = null
    lb_annotations       = { "service.beta.kubernetes.io/aws-load-balancer-type" = "external" }
  }
  assert {
    condition     = output.contract.gateway_node_port == null && output.contract.gateway_service_type == "LoadBalancer"
    error_message = "LoadBalancer contract should have no node port"
  }
}

run "rejects_unknown_provider" {
  command = plan
  variables { provider_name = "openstack" }
  expect_failures = [var.provider_name]
}

run "rejects_http_endpoint" {
  command = plan
  variables { cluster_endpoint = "http://127.0.0.1:6443" }
  expect_failures = [var.cluster_endpoint]
}

run "rejects_relative_kubeconfig" {
  command = plan
  variables { kubeconfig_path = "build/kubeconfig" }
  expect_failures = [var.kubeconfig_path]
}

run "rejects_unknown_gateway_type" {
  command = plan
  variables { gateway_service_type = "Ingress" }
  expect_failures = [var.gateway_service_type]
}

run "rejects_nodeport_without_port" {
  command = plan
  variables { gateway_node_port = null }
  expect_failures = [var.gateway_node_port]
}

run "rejects_nodeport_out_of_range" {
  command = plan
  variables { gateway_node_port = 8080 }
  expect_failures = [var.gateway_node_port]
}

run "rejects_port_with_load_balancer" {
  command = plan
  variables {
    gateway_service_type = "LoadBalancer"
    gateway_node_port    = 30080
  }
  expect_failures = [var.gateway_node_port]
}
