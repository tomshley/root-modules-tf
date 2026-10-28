# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
