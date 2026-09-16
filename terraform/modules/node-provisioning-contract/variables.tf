variable "contract" {
  type = object({
    capacity_types = set(string)
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    max_cpu             = string
    max_memory          = string
    disruption_policy   = string
    controller_required = bool
  })
  nullable    = false
  description = "Provider-independent node scheduling and disruption intent."

  validation {
    condition = length(var.contract.capacity_types) > 0 && alltrue([
      for value in var.contract.capacity_types : contains(["on-demand", "spot"], value)
    ])
    error_message = "capacity_types must contain on-demand or spot values."
  }

  validation {
    condition = alltrue([
      for taint in var.contract.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], taint.effect)
    ])
    error_message = "taints[*].effect must be a supported Kubernetes taint effect."
  }

  validation {
    condition     = can(regex("^[1-9][0-9]*([mMgG])?$", var.contract.max_cpu))
    error_message = "max_cpu must be a positive resource quantity."
  }

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.contract.max_memory))
    error_message = "max_memory must be a positive binary memory quantity."
  }

  validation {
    condition     = contains(["when-empty", "when-empty-or-underutilized", "disabled"], var.contract.disruption_policy)
    error_message = "disruption_policy must be when-empty, when-empty-or-underutilized, or disabled."
  }
}
