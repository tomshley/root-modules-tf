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

terraform {
  # optional(...) object attributes with defaults in metric_rules/log_rules.
  required_version = ">= 1.3"

  required_providers {
    grafana = {
      source = "grafana/grafana"
      # >= 2.9.0 : per-rule `notification_settings` (simplified routing; also
      #            requires Grafana 10.4+ on the target instance).
      # <  3.0.0 : the v3 provider renames/relocates several alerting resources;
      #            bump deliberately after re-testing, do not let it float.
      version = ">= 2.9.0, < 3.0.0"
    }
  }
}
