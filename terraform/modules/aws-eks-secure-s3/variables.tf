variable "project_name_prefix" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "force_destroy" {
  type    = bool
  default = false
}

variable "versioning_enabled" {
  type    = bool
  default = false
}

variable "lifecycle_expiration_days" {
  type    = number
  default = 0
}

variable "lifecycle_glacier_transition_days" {
  type    = number
  default = 0
}

variable "lifecycle_deep_archive_transition_days" {
  type    = number
  default = 0
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
  type    = string
  default = ""
}

variable "logging_target_bucket" {
  type    = string
  default = ""
}

variable "logging_target_prefix" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
