variable "project_id" { type = string }
variable "cluster_name" { type = string }
variable "cluster_location" { type = string }
variable "node_location" { type = string }
variable "controller_google_service_account_email" { type = string }
variable "node_service_account_email" { type = string }
variable "namespace" {
  type    = string
  default = "karpenter-system"
}
variable "kubernetes_service_account_name" {
  type    = string
  default = "karpenter"
}
variable "node_network_tags" {
  type    = set(string)
  default = []
}
variable "create_namespace" {
  type    = bool
  default = true
}
variable "extra_helm_values" {
  type    = list(string)
  default = []
}
