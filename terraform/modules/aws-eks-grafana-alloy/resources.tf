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

module "alloy" {
  source = "../k8s-grafana-alloy"

  enabled                                    = var.enabled
  cluster_name                               = var.cluster_name
  chart_version                              = var.chart_version
  namespace                                  = var.namespace
  create_namespace                           = var.create_namespace
  prometheus_url                             = var.prometheus_url
  prometheus_username                        = var.prometheus_username
  loki_url                                   = var.loki_url
  loki_username                              = var.loki_username
  grafana_cloud_token                        = var.grafana_cloud_token
  credentials_secret_name                    = var.credentials_secret_name
  credentials_secret_namespace               = var.credentials_secret_namespace
  credentials_secret_token_key               = var.credentials_secret_token_key
  credentials_secret_prometheus_username_key = var.credentials_secret_prometheus_username_key
  credentials_secret_loki_username_key       = var.credentials_secret_loki_username_key
  cluster_metrics_enabled                    = var.cluster_metrics_enabled
  cluster_events_enabled                     = var.cluster_events_enabled
  pod_logs_enabled                           = var.pod_logs_enabled
  annotation_autodiscovery_enabled           = var.annotation_autodiscovery_enabled
  prometheus_operator_objects_enabled        = var.prometheus_operator_objects_enabled
  helm_timeout                               = var.helm_timeout
  extra_helm_values                          = var.extra_helm_values
}
