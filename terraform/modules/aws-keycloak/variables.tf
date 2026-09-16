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
variable "keycloak_chart_version" {
  type    = string
  default = "24.4.2"
}
variable "keycloak_image_tag" {
  type    = string
  default = null
}
variable "db_secret_arn" { type = string }
variable "db_endpoint" { type = string }
variable "db_port" {
  type    = number
  default = 5432
}
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password" {
  type      = string
  default   = null
  sensitive = true
}
variable "admin_secret_arn" {
  type    = string
  default = null
}
variable "admin_user" {
  type    = string
  default = "admin"
}
variable "admin_password" {
  type      = string
  default   = null
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
  type    = map(string)
  default = {}
}
variable "db_secret_annotations" {
  type    = map(string)
  default = {}
}
variable "admin_secret_annotations" {
  type    = map(string)
  default = {}
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
