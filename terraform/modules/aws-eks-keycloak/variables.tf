variable "release_name" {
  description = "Name of the Helm release and prefix for all K8s resources (secrets, configmap). Must be unique within the namespace when deploying multiple Keycloak instances."
  type        = string
  default     = "keycloak"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9]*(-[a-z0-9]+)*)?$", var.release_name)) && length(var.release_name) <= 53
    error_message = "release_name must be a valid DNS label (lowercase alphanumeric + hyphens, max 53 chars)."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Keycloak"
  type        = string
  default     = "identity"
}

variable "create_namespace" {
  description = "Whether to create the namespace if it does not exist"
  type        = bool
  default     = true
}

variable "keycloak_chart_version" {
  description = "Bitnami Keycloak Helm chart version"
  type        = string
  default     = "24.4.2"
}

variable "keycloak_image_tag" {
  description = "Keycloak container image tag (overrides chart default)"
  type        = string
  default     = null
}

# --- Database connection (from aws-eks-aurora-cluster outputs) ---

variable "db_secret_arn" {
  description = "Secrets Manager ARN containing database credentials (username, password, host, port, dbname). From aws-eks-aurora-cluster master_secret_arn output."
  type        = string
}

variable "db_endpoint" {
  description = "Aurora cluster writer endpoint. From aws-eks-aurora-cluster cluster_endpoint output."
  type        = string
}

variable "db_port" {
  description = "Aurora cluster port. From aws-eks-aurora-cluster port output."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name for Keycloak. From aws-eks-aurora-cluster database_name output."
  type        = string
}

variable "db_user" {
  description = "Database user for Keycloak. Must match the master username in the Aurora cluster secret."
  type        = string
}

variable "db_password" {
  description = "Database password for Keycloak. When null, resolved from Secrets Manager via db_secret_arn at plan time — no ExternalSecretsOperator required for first apply. Note: ignore_changes on the K8s secret data means subsequent changes to this variable are not applied — taint kubernetes_secret.db_credentials to rotate."
  type        = string
  default     = null
  sensitive   = true
}

# --- Admin credentials ---

variable "admin_secret_arn" {
  description = "Secrets Manager ARN containing Keycloak admin credentials (username, password). Required when admin_password is null."
  type        = string
  default     = null
}

variable "admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Keycloak admin password. When null, resolved from Secrets Manager via admin_secret_arn at plan time — no ExternalSecretsOperator required for first apply. Note: ignore_changes on the K8s secret data means subsequent changes to this variable are not applied — taint kubernetes_secret.admin_credentials to rotate."
  type        = string
  default     = null
  sensitive   = true
}

# --- Realm import ---

variable "realm_json_path" {
  description = "Local filesystem path to the realm JSON file to import. Set to null to skip realm import. Resolved by Terraform file() relative to the root module working directory — use path.module in the consumer to build an absolute path."
  type        = string
  default     = null
}

# --- Networking ---

variable "service_port" {
  description = "Kubernetes Service port for Keycloak HTTP. Reflects the Bitnami chart default (HTTP/80). Override if TLS termination or a non-standard port is configured via extra_helm_values."
  type        = number
  default     = 80

  validation {
    condition     = var.service_port >= 1 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port (1-65535)."
  }
}

variable "service_type" {
  description = "Kubernetes Service type for Keycloak (ClusterIP, LoadBalancer, NodePort)"
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "LoadBalancer", "NodePort"], var.service_type)
    error_message = "service_type must be one of: ClusterIP, LoadBalancer, NodePort."
  }
}

variable "replicas" {
  description = "Number of Keycloak replicas"
  type        = number
  default     = 1

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

# --- Resource limits ---

variable "resources_requests_cpu" {
  description = "CPU request for Keycloak pods"
  type        = string
  default     = "500m"
}

variable "resources_requests_memory" {
  description = "Memory request for Keycloak pods"
  type        = string
  default     = "512Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit for Keycloak pods"
  type        = string
  default     = "1000m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Keycloak pods"
  type        = string
  default     = "1024Mi"
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds. Keycloak runs DB migrations on first boot, so the default is higher than lightweight chart modules."
  type        = number
  default     = 600
}

variable "extra_helm_values" {
  description = "Additional Helm values YAML strings appended after module-managed values. Last value wins (standard Helm merge semantics). Use for TLS, ingress, extra env vars, or any chart value not exposed as a module variable."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied as Kubernetes labels to all managed resources"
  type        = map(string)
  default     = {}
}
