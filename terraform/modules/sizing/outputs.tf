output "node_pools" {
  description = "Input node pools, each with instance_type, vcpu and memory_gib added."
  value = [
    for p in var.node_pools : merge(p, {
      instance_type = local.catalog[var.cloud][p.size]
      vcpu          = local.shapes[p.size].vcpu
      memory_gib    = local.shapes[p.size].memory_gib
    })
  ]
}
