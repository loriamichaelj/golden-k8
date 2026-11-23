output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "azs" {
  description = "Availability zones in use."
  value       = local.azs
}

output "private_subnet_ids" {
  description = "Private subnet IDs (empty when privateSubnets is false)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "node_subnet_ids" {
  description = "Subnets the nodes run in: private when privateSubnets is true, else public."
  value       = var.private_subnets ? module.vpc.private_subnets : module.vpc.public_subnets
}

output "private_subnet_cidrs" {
  description = "Private subnet ranges."
  value       = local.private_cidrs
}

output "public_subnet_cidrs" {
  description = "Public subnet ranges."
  value       = local.public_cidrs
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = module.vpc.natgw_ids
}
