locals {
  normalized = {
    capacity_types      = sort(tolist(var.contract.capacity_types))
    labels              = var.contract.labels
    taints              = var.contract.taints
    max_cpu             = var.contract.max_cpu
    max_memory          = var.contract.max_memory
    disruption_policy   = var.contract.disruption_policy
    controller_required = var.contract.controller_required
  }
}
