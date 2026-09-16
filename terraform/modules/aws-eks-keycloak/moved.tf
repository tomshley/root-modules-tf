moved {
  from = data.aws_secretsmanager_secret_version.db
  to   = module.keycloak.data.aws_secretsmanager_secret_version.db
}

moved {
  from = data.aws_secretsmanager_secret_version.admin
  to   = module.keycloak.data.aws_secretsmanager_secret_version.admin
}

moved {
  from = kubernetes_namespace.keycloak
  to   = module.keycloak.module.keycloak.kubernetes_namespace.keycloak
}

moved {
  from = kubernetes_secret.db_credentials
  to   = module.keycloak.module.keycloak.kubernetes_secret.db_credentials
}

moved {
  from = kubernetes_secret.admin_credentials
  to   = module.keycloak.module.keycloak.kubernetes_secret.admin_credentials
}

moved {
  from = kubernetes_config_map.realm_import
  to   = module.keycloak.module.keycloak.kubernetes_config_map.realm_import
}

moved {
  from = helm_release.keycloak
  to   = module.keycloak.module.keycloak.helm_release.keycloak
}
