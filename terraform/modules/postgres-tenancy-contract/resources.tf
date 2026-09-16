locals {
  bindings = {
    for key, tenant in var.tenants : key => {
      tenant_key    = key
      database_name = tenant.database_name
      db_role_name  = tenant.db_role_name != null ? tenant.db_role_name : replace(key, "-", "_")
    }
  }
}
