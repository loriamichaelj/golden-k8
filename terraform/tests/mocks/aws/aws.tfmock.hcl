# Shared mock data for mock_provider "aws" (terraform test). Values only where
# a module indexes into them or the provider schema validates their format;
# everything else is generated. Placeholder account 111122223333.

mock_data "aws_availability_zones" {
  defaults = {
    names = ["us-east-1c", "us-east-1a", "us-east-1b", "us-east-1d"]
  }
}

mock_data "aws_partition" {
  defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
}

mock_data "aws_caller_identity" {
  defaults = { account_id = "111122223333", arn = "arn:aws:iam::111122223333:role/example" }
}

mock_data "aws_iam_session_context" {
  defaults = { issuer_arn = "arn:aws:iam::111122223333:role/example" }
}

mock_data "aws_iam_policy_document" {
  defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

mock_data "aws_eks_addon_version" {
  defaults = { version = "v1.0.0-eksbuild.1" }
}

mock_resource "aws_eks_cluster" {
  defaults = {
    arn                   = "arn:aws:eks:us-east-1:111122223333:cluster/golden-test"
    endpoint              = "https://EXAMPLE0123.gr7.us-east-1.eks.amazonaws.com"
    certificate_authority = [{ data = "LS0tLS1CRUdJTi0tLS0t" }]
  }
}

mock_resource "aws_launch_template" {
  defaults = {
    id  = "lt-0123456789abcdef0"
    arn = "arn:aws:ec2:us-east-1:111122223333:launch-template/lt-0123456789abcdef0"
  }
}

mock_resource "aws_iam_policy" {
  defaults = { arn = "arn:aws:iam::111122223333:policy/golden-test" }
}

mock_resource "aws_iam_role" {
  defaults = { arn = "arn:aws:iam::111122223333:role/golden-test" }
}

mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000" }
}
