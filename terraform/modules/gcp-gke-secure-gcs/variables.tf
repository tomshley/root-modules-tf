variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "bucket_name" {
  type        = string
  description = "Globally unique Cloud Storage bucket name."
}

variable "location" {
  type        = string
  description = "Cloud Storage location."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to delete non-empty bucket contents."
}

variable "versioning_enabled" {
  type        = bool
  default     = false
  description = "Enable object versioning."
}

variable "retention_policy_days" {
  type        = number
  default     = 0
  description = "Retention period in days. Zero disables a bucket retention policy."

  validation {
    condition     = var.retention_policy_days >= 0
    error_message = "retention_policy_days must be zero or greater."
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to the bucket."
}
