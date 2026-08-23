variable "project_name_prefix" {
  type        = string
  description = "Project name prefix for resource naming."

  validation {
    condition     = var.project_name_prefix != "" && var.project_name_prefix == trimspace(var.project_name_prefix)
    error_message = "project_name_prefix must be non-empty and carry no leading/trailing whitespace."
  }
}

variable "role_name_suffix" {
  type        = string
  description = "Suffix for the IAM role name (e.g. 'infrastructure-deploy', 'gitlab-deploy'). Final name: {project_name_prefix}-ci-{role_name_suffix}."

  validation {
    condition     = var.role_name_suffix != "" && var.role_name_suffix == trimspace(var.role_name_suffix)
    error_message = "role_name_suffix must be non-empty and carry no leading/trailing whitespace."
  }

  # IAM role names are capped at 64 characters; fail at plan time with the
  # offending lengths named rather than at apply with an opaque API error.
  validation {
    condition     = length(var.project_name_prefix) + length("-ci-") + length(var.role_name_suffix) <= 64
    error_message = "The IAM role name {project_name_prefix}-ci-{role_name_suffix} exceeds AWS's 64-character limit — shorten one of the two inputs."
  }
}

variable "oidc_provider_arn" {
  type        = string
  default     = null
  description = "Existing IAM OIDC provider ARN to reuse. When null, this module creates the provider — AWS allows a single provider per issuer URL per account, so pass the ARN wherever one already exists."

  validation {
    condition     = var.oidc_provider_arn == null || can(regex(":oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN containing ':oidc-provider/'."
  }
}

variable "issuer_url" {
  type        = string
  default     = null
  description = "OIDC issuer URL of the CI platform. Required when creating a new provider (oidc_provider_arn = null); when reusing a provider this may stay null and the issuer is derived from the ARN."

  validation {
    condition     = var.issuer_url != null || var.oidc_provider_arn != null
    error_message = "Set issuer_url (to create the OIDC provider) or oidc_provider_arn (to reuse an existing one) — with neither, there is no issuer to build trust against."
  }
}

variable "audiences" {
  type        = list(string)
  default     = ["sts.amazonaws.com"]
  description = "Allowed audiences for the OIDC provider. The default is the STS audience most CI platforms present to AWS; override where the platform is configured with a custom audience."

  validation {
    condition     = length(var.audiences) > 0
    error_message = "audiences must contain at least one entry — the provider's client ID list cannot be empty."
  }
}

variable "thumbprints" {
  type        = list(string)
  default     = []
  description = "TLS certificate thumbprints for the OIDC provider. Empty is valid for issuers whose root CA is in AWS's trust store."
}

variable "conditions" {
  type = list(object({
    claim  = string
    match  = string
    values = list(string)
  }))
  description = "Trust conditions in the ci-oidc-trust contract shape: claim, match = \"exact\" | \"wildcard\", values. Translated here as exact -> StringEquals and wildcard -> StringLike on {issuer_host}:{claim}. Validation lives in ci-oidc-trust."
}

variable "policy_arns" {
  type        = list(string)
  default     = []
  description = "IAM policy ARNs to attach to the role (the role's permissions; trust only restricts who assumes it)."
}

variable "max_session_duration" {
  type        = number
  default     = 3600
  description = "Maximum session duration in seconds for the role (3600–43200)."

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds (AWS constraint)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources."
}
