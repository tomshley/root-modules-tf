variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for all resources created by this module"
}

variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to destroy the bucket even if it contains objects"
}

variable "versioning_enabled" {
  type        = bool
  default     = false
  description = "Enable S3 object versioning"
}

variable "lifecycle_expiration_days" {
  type        = number
  default     = 0
  description = "Days after which objects expire (0 = disabled)"
}

variable "lifecycle_glacier_transition_days" {
  type        = number
  default     = 0
  description = "Days after which objects transition to Glacier (0 = disabled)"
}

variable "lifecycle_deep_archive_transition_days" {
  type        = number
  default     = 0
  description = "Days after which objects transition to Deep Archive (0 = disabled, must be >= glacier days)"
}

variable "sse_algorithm" {
  type    = string
  default = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be AES256 or aws:kms."
  }
}

variable "kms_key_id" {
  type        = string
  default     = ""
  description = "KMS key ID for server-side encryption (required when sse_algorithm is aws:kms)"
}

variable "logging_target_bucket" {
  type        = string
  default     = ""
  description = "Target bucket for access logging (empty = logging disabled)"
}

variable "logging_target_prefix" {
  type        = string
  default     = ""
  description = "Prefix for access log objects in the target bucket"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
