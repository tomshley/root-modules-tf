variable "release_name" {
  type    = string
  default = "keycloak"
}
variable "namespace" {
  type    = string
  default = "identity"
}
variable "create_namespace" {
  type    = bool
  default = true
}
variable "chart_version" {
  type    = string
  default = "24.4.2"
}
variable "image_tag" {
  type    = string
  default = null
}
variable "db_endpoint" { type = string }
variable "db_port" {
  type    = number
  default = 5432
}
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "admin_user" {
  type    = string
  default = "admin"
}
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "realm_json_path" {
  type    = string
  default = null
}
variable "service_port" {
  type    = number
  default = 80
}
variable "service_type" {
  type    = string
  default = "ClusterIP"
}
variable "replicas" {
  type    = number
  default = 1
}
variable "pod_annotations" {
  type    = map(string)
  default = {}
}
variable "labels" {
  type        = map(string)
  default     = {}
  description = "Provider-neutral labels applied to Kubernetes resources."
}
variable "db_secret_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations applied to the database credentials Secret by the provider adapter."
}
variable "admin_secret_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations applied to the admin credentials Secret by the provider adapter."
}
variable "resources_requests_cpu" {
  type    = string
  default = "500m"
}
variable "resources_requests_memory" {
  type    = string
  default = "512Mi"
}
variable "resources_limits_cpu" {
  type    = string
  default = "1000m"
}
variable "resources_limits_memory" {
  type    = string
  default = "1024Mi"
}
variable "helm_timeout" {
  type    = number
  default = 600
}
variable "extra_helm_values" {
  type    = list(string)
  default = []
}
