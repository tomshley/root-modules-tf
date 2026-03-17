variable "google_organization_id" {
  type = string
}

variable "google_billing_account" {
  type = string
}

variable "google_project_id" {
  type = string
}

variable "project_name_prefix" {
  type = string
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels to apply to the GCP project"
}
