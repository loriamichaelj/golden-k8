# The parity check itself: accepts a v1 contract, rejects drift.

variables {
  contract = {
    contract_version     = "v1"
    provider             = "aws"
    cluster_name         = "golden-test"
    cluster_endpoint     = "https://example.invalid"
    kubeconfig_path      = "/tmp/kubeconfig"
    kube_context         = "golden-test"
    storage_class        = ""
    gateway_service_type = "LoadBalancer"
    gateway_node_port    = null
    lb_annotations       = { "example.com/annotation" = "value" }
    network_id           = "vpc-1"
    private_subnet_ids   = ["subnet-1"]
  }
}

run "accepts_v1" {
  command = plan
}

run "rejects_missing_key" {
  command = plan
  variables {
    contract = {
      contract_version = "v1", provider = "aws", cluster_name = "c", cluster_endpoint = "https://e", kubeconfig_path = "/k",
      kube_context     = "c", storage_class = "", gateway_service_type = "LoadBalancer", gateway_node_port = null,
      lb_annotations   = {}, network_id = ""
    }
  }
  expect_failures = [var.contract]
}

run "rejects_extra_key" {
  command = plan
  variables {
    contract = {
      contract_version = "v1", provider = "aws", cluster_name = "c", cluster_endpoint = "https://e", kubeconfig_path = "/k",
      kube_context     = "c", storage_class = "", gateway_service_type = "LoadBalancer", gateway_node_port = null,
      lb_annotations   = {}, network_id = "", private_subnet_ids = [], region = "us-east-1"
    }
  }
  expect_failures = [var.contract]
}

run "rejects_wrong_types" {
  command = plan
  variables {
    contract = {
      contract_version = "v1", provider = "aws", cluster_name = "c", cluster_endpoint = "https://e", kubeconfig_path = "/k",
      kube_context     = "c", storage_class = "", gateway_service_type = "LoadBalancer", gateway_node_port = "30080x",
      lb_annotations   = ["a"], network_id = "", private_subnet_ids = "subnet-1"
    }
  }
  expect_failures = [var.contract]
}

run "rejects_other_version" {
  command = plan
  variables {
    contract = {
      contract_version = "v2", provider = "aws", cluster_name = "c", cluster_endpoint = "https://e", kubeconfig_path = "/k",
      kube_context     = "c", storage_class = "", gateway_service_type = "LoadBalancer", gateway_node_port = null,
      lb_annotations   = {}, network_id = "", private_subnet_ids = []
    }
  }
  expect_failures = [var.contract]
}
