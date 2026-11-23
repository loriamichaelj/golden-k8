output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
}

output "node_groups" {
  description = "Managed node group settings per pool, as passed to EKS."
  value       = local.node_groups
}

output "node_group_labels" {
  description = "Kubernetes labels each created node group carries."
  value       = { for name, ng in module.eks.eks_managed_node_groups : name => ng.node_group_labels }
}
