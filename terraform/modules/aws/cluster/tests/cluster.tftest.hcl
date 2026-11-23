# Mocked AWS provider (shared mocks in terraform/tests/mocks/aws): no
# credentials, no API calls, no cost.

mock_provider "aws" {
  source = "../../../tests/mocks/aws"
}

variables {
  name               = "golden-test"
  kubernetes_version = "1.36"
  vpc_id             = "vpc-0123456789abcdef0"
  node_subnet_ids    = ["subnet-a", "subnet-b", "subnet-c"]
  node_pools = [
    { name = "system", size = "small", min = 2, max = 3, instance_type = "m7i.large" },
    { name = "apps", size = "medium", min = 1, max = 5, instance_type = "m7i.xlarge" },
  ]
}

run "node_groups_from_pools" {
  assert {
    condition     = keys(output.node_groups) == ["apps", "system"]
    error_message = "expected one managed node group per pool"
  }
  assert {
    condition = (
      output.node_groups.system.instance_types == ["m7i.large"] &&
      output.node_groups.system.min_size == 2 && output.node_groups.system.max_size == 3 &&
      output.node_groups.system.desired_size == 2
    )
    error_message = "system pool: small → m7i.large, min 2, max 3, desired = min"
  }
  assert {
    condition = (
      output.node_groups.apps.instance_types == ["m7i.xlarge"] &&
      output.node_groups.apps.min_size == 1 && output.node_groups.apps.max_size == 5
    )
    error_message = "apps pool: medium → m7i.xlarge, min 1, max 5"
  }
  assert {
    condition     = output.node_group_labels.apps["golden-k8/pool"] == "apps" && output.node_group_labels.system["golden-k8/size"] == "small"
    error_message = "node groups should carry golden-k8/pool and golden-k8/size labels"
  }
  assert {
    condition     = output.cluster_endpoint == "https://EXAMPLE0123.gr7.us-east-1.eks.amazonaws.com"
    error_message = "cluster_endpoint should come from the EKS cluster"
  }
}

run "cluster_settings" {
  assert {
    condition     = module.eks.cluster_version == "1.36" && module.eks.cluster_name == "golden-test"
    error_message = "cluster should be named golden-test and run Kubernetes 1.36"
  }
  assert {
    condition     = toset(keys(module.eks.cluster_addons)) == toset(["aws-ebs-csi-driver", "coredns", "eks-pod-identity-agent", "kube-proxy", "metrics-server", "vpc-cni"])
    error_message = "expected the core add-ons, metrics-server and the EBS CSI driver"
  }
  assert {
    condition     = jsondecode(module.eks.cluster_addons["aws-ebs-csi-driver"].configuration_values).defaultStorageClass.enabled
    error_message = "the EBS CSI add-on should create the gp3 default StorageClass"
  }
  assert {
    condition     = module.eks.oidc_provider_arn == null
    error_message = "IRSA should be off (EKS Pod Identity instead)"
  }
  assert {
    condition     = aws_iam_role_policy_attachment.ebs_csi.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    error_message = "the EBS CSI role needs the managed AmazonEBSCSIDriverPolicy"
  }
}

run "pool_min_over_max" {
  command = plan
  variables {
    node_pools = [{ name = "system", size = "small", min = 4, max = 3, instance_type = "m7i.large" }]
  }
  expect_failures = [var.node_pools]
}
