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

output "active_topics" {
  description = "Map of active topic name to its attributes after overlay filtering."
  value       = local.active_topics
}

output "active_topic_summary" {
  description = "Summary of topics created in this deployment after overlay filtering."
  value = {
    by_role = {
      for role in distinct([for t in values(local.active_topics) : t.role]) :
      role => length([for t in values(local.active_topics) : t if t.role == role])
    }
    by_service = {
      for svc in distinct([for t in values(local.active_topics) : t.service]) :
      svc => [for t in values(local.active_topics) : t.name if t.service == svc]
    }
    total = length(local.active_topics)
    names = [for t in values(local.active_topics) : t.name]
  }
}

output "catalog_summary" {
  description = "Summary of all topics from the input catalog (before overlay filtering)."
  value = {
    by_role = {
      for role in distinct([for t in var.catalog_entries : t.role]) :
      role => length([for t in var.catalog_entries : t if t.role == role])
    }
    by_service = {
      for svc in distinct([for t in var.catalog_entries : t.service]) :
      svc => [for t in var.catalog_entries : t.name if t.service == svc]
    }
    total = length(var.catalog_entries)
    names = [for t in var.catalog_entries : t.name]
  }
}
