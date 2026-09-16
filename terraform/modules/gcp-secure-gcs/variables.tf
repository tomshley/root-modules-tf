variable "project_id" { type = string }
variable "bucket_name" { type = string }
variable "location" { type = string }
variable "force_destroy" {
  type    = bool
  default = false
}
variable "versioning_enabled" {
  type    = bool
  default = false
}
variable "retention_policy_days" {
  type    = number
  default = 0
  validation {
    condition     = var.retention_policy_days >= 0
    error_message = "retention_policy_days must be zero or greater."
  }
}
variable "labels" {
  type    = map(string)
  default = {}
}
