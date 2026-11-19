output "contract" {
  description = "Outputs contract consumed by Ansible (written to build/contract.json)."
  value = {
    contract_version     = "v1"
    provider             = var.provider_name
    cluster_name         = var.cluster_name
    cluster_endpoint     = var.cluster_endpoint
    kubeconfig_path      = var.kubeconfig_path
    kube_context         = var.kube_context
    storage_class        = var.storage_class
    gateway_service_type = var.gateway_service_type
    gateway_node_port    = var.gateway_node_port
    lb_annotations       = var.lb_annotations
    network_id           = var.network_id
    private_subnet_ids   = var.private_subnet_ids
  }
}
