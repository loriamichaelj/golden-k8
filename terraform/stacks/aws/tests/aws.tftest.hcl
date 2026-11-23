# Plan/apply against mocked providers: no AWS credentials, no API calls, no
# cost. Fixtures come from terraform/tests/fixtures/*.yaml and
# environments/*-example.yaml, normalized into build/test-fixtures/ by
# scripts/test-terraform.sh.

mock_provider "aws" {
  source = "../../tests/mocks/aws"
}

# The kubeconfig is not written, and the EKS module's time_sleep doesn't wait.
mock_provider "local" {}
mock_provider "time" {}
mock_provider "tls" {}

variables {
  build_dir = "/tmp/golden-k8-test"
}

run "defaults" {
  variables { config_path = "../../../build/test-fixtures/aws-minimal.json" }

  assert {
    condition     = length(module.network.azs) == 3 && length(output.network.private_subnet_ids) == 3 && length(output.network.nat_gateway_ids) == 1
    error_message = "default network: 3 zones, 3 private subnets, 1 NAT gateway"
  }
  assert {
    condition     = jsonencode(keys(output.node_groups)) == jsonencode(["system"])
    error_message = "default cluster: one system pool"
  }
  assert {
    condition     = jsonencode(output.node_groups.system.instance_types) == jsonencode(["m7i.large"]) && output.node_groups.system.min_size == 2 && output.node_groups.system.max_size == 3
    error_message = "system pool: small → m7i.large, min 2, max 3"
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
  variables { config_path = "../../../build/test-fixtures/aws-minimal.json" }

  assert {
    condition = (
      output.contract.contract_version == "v1" &&
      output.contract.provider == "aws" &&
      output.contract.cluster_name == "golden-test" &&
      output.contract.cluster_endpoint == "https://EXAMPLE0123.gr7.us-east-1.eks.amazonaws.com" &&
      output.contract.kubeconfig_path == "/tmp/golden-k8-test/kubeconfig-golden-test" &&
      output.contract.kube_context == "arn:aws:eks:us-east-1:111122223333:cluster/golden-test" &&
      output.contract.storage_class == "ebs-csi-default-sc" &&
      output.contract.gateway_service_type == "LoadBalancer" &&
      output.contract.gateway_node_port == null &&
      jsonencode(output.contract.lb_annotations) == jsonencode({ "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb" }) &&
      output.contract.network_id == module.network.vpc_id &&
      length(output.contract.private_subnet_ids) == 3
    )
    error_message = "aws contract values are wrong"
  }
}

run "contract_parity" {
  module { source = "../../tests/parity" }
  variables { contract = run.contract.contract }
}

run "kubeconfig_uses_aws_cli" {
  variables { config_path = "../../../build/test-fixtures/aws-minimal.json" }

  assert {
    condition = (
      yamldecode(local_file.kubeconfig.content).users[0].user.exec.command == "aws" &&
      jsonencode(yamldecode(local_file.kubeconfig.content).users[0].user.exec.args) == jsonencode(["--region", "us-east-1", "eks", "get-token", "--cluster-name", "golden-test", "--output", "json"]) &&
      yamldecode(local_file.kubeconfig.content).clusters[0].cluster.server == output.contract.cluster_endpoint &&
      local_file.kubeconfig.file_permission == "0600"
    )
    error_message = "kubeconfig should use aws eks get-token for the cluster, with no stored credentials"
  }
}

run "tags" {
  variables { config_path = "../../../build/test-fixtures/aws-overrides.json" }

  assert {
    condition = (
      local.tags["golden-k8/environment"] == "test" &&
      local.tags["golden-k8/managed"] == "true" &&
      local.tags["golden-k8/owner"] == "platform" &&
      local.tags["team"] == "example"
    )
    error_message = "default_tags should carry metadata.tags plus golden-k8 environment, owner and managed"
  }
}

run "overrides" {
  variables { config_path = "../../../build/test-fixtures/aws-overrides.json" }

  assert {
    condition = jsonencode(output.contract.lb_annotations) == jsonencode({
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    })
    error_message = "providerOverrides.lbAnnotations should be merged over the platform defaults"
  }
  assert {
    condition     = module.cluster.node_groups != null && module.cluster.cluster_endpoint != ""
    error_message = "cluster should still plan with overrides"
  }
}

run "public_only" {
  variables { config_path = "../../../build/test-fixtures/aws-public-only.json" }

  assert {
    condition     = length(output.network.private_subnet_ids) == 0 && length(output.network.public_subnet_ids) == 1 && length(output.network.nat_gateway_ids) == 0
    error_message = "privateSubnets false + natGateway none: one public subnet, no NAT"
  }
  assert {
    condition     = length(output.contract.private_subnet_ids) == 0
    error_message = "contract should list no private subnets"
  }
  assert {
    condition     = jsonencode(output.node_groups.system.instance_types) == jsonencode(["m7i.2xlarge"])
    error_message = "large → m7i.2xlarge"
  }
}

run "example" {
  variables { config_path = "../../../build/test-fixtures/env-aws-example.json" }

  assert {
    condition     = toset(keys(output.node_groups)) == toset(["system", "apps"])
    error_message = "environments/aws-example.yaml: system and apps pools"
  }
  assert {
    condition     = jsonencode(output.node_groups.apps.instance_types) == jsonencode(["m7i.xlarge"]) && output.node_groups.apps.max_size == 5
    error_message = "apps pool: medium → m7i.xlarge, max 5"
  }
}

run "wrong_provider" {
  command = plan
  variables { config_path = "../../../build/test-fixtures/local-default.json" }
  expect_failures = [var.config_path]
}
