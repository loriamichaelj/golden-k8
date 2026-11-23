# AWS network: a VPC with public subnets (load balancers, NAT) and, when
# spec.network.privateSubnets is true, private subnets for the nodes.
#
# Address plan, for a /16 (scales down to /20):
#   private  cidrsubnet(cidr, 2, i)       3 × /18  nodes and pods (VPC CNI uses VPC IPs)
#   public   cidrsubnet(cidr, 6, 48 + i)  3 × /22  load balancers and NAT, in the last /18

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(sort(data.aws_availability_zones.available.names), 0, var.az_count)

  private_cidrs = var.private_subnets ? [for i in range(var.az_count) : cidrsubnet(var.cidr, 2, i)] : []
  public_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.cidr, 6, 48 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  private_subnets = local.private_cidrs
  public_subnets  = local.public_cidrs

  # Nodes in public subnets need public addresses for egress; behind NAT they don't.
  map_public_ip_on_launch = !var.private_subnets

  enable_nat_gateway     = var.private_subnets && var.nat_gateway != "none"
  single_nat_gateway     = var.nat_gateway == "single"
  one_nat_gateway_per_az = var.nat_gateway == "perZone"

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet discovery for Service type LoadBalancer (EKS cloud controller and
  # the AWS Load Balancer Controller).
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = var.tags
}

check "zones" {
  assert {
    condition     = length(local.azs) == var.az_count
    error_message = "The region has fewer than ${var.az_count} availability zones that need no opt-in."
  }
}
