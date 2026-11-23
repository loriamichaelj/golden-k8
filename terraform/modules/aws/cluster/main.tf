# AWS cluster: EKS with one managed node group per spec.cluster.nodePools
# entry, the core add-ons, and the EBS CSI driver (Pod Identity) providing a
# gp3 default StorageClass.

data "aws_partition" "current" {}

locals {
  node_groups = {
    for p in var.node_pools : p.name => {
      name           = p.name
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [p.instance_type]
      min_size       = p.min
      max_size       = p.max
      desired_size   = p.min
      labels         = { "golden-k8/pool" = p.name, "golden-k8/size" = p.size }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.node_subnet_ids

  # Private endpoint always; a public one only for the ranges you list
  # (providerOverrides.endpointPublicAccessCidrs), e.g. where the pipeline runs.
  endpoint_private_access      = true
  endpoint_public_access       = length(var.endpoint_public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Access entries only; whoever applies becomes cluster admin.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Workload identity through EKS Pod Identity, so no OIDC provider (IRSA).
  enable_irsa = false

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    coredns                = {}
    kube-proxy             = {}
    metrics-server         = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
      # The add-on creates a gp3 StorageClass named ebs-csi-default-sc and marks it default.
      configuration_values = jsonencode({ defaultStorageClass = { enabled = true } })
    }
  }

  eks_managed_node_groups = local.node_groups

  tags = var.tags
}

# EBS CSI controller identity (EKS Pod Identity).
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name_prefix        = "${substr(var.name, 0, 20)}-ebs-csi-"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
