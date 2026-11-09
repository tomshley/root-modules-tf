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

locals {
  ios_apps     = [for app in var.apps : app.ios if try(app.ios, null) != null]
  android_apps = [for app in var.apps : app.android if try(app.android, null) != null]
  files = merge(
    length(local.ios_apps) == 0 ? {} : {
      "/.well-known/apple-app-site-association" = {
        content = jsonencode({
          applinks = {
            details = [for app in local.ios_apps : {
              appIDs     = ["${app.team_id}.${app.bundle_id}"]
              components = [for path in app.paths : { "/" = path }]
            }]
          }
        })
        content_type = "application/json"
      }
    },
    length(local.android_apps) == 0 ? {} : {
      "/.well-known/assetlinks.json" = {
        content = jsonencode([for app in local.android_apps : {
          relation = ["delegate_permission/common.handle_all_urls"]
          target = {
            namespace                = "android_app"
            package_name             = app.package_name
            sha256_cert_fingerprints = app.sha256_fingerprints
          }
        }])
        content_type = "application/json"
      }
    }
  )
}
