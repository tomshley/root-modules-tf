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
  image_digests = {
    controller      = "sha256:9f4f96a33c7774cef24466fcd85031997531a03a8d117f151126baa8d1290dcc"
    webhook         = "sha256:055ac8e9de6a0ba6763794838fe38944acc650f68ebe1b01dd8be079e580f458"
    cainjector      = "sha256:083d0e906f8eb44e255fe4ff817ae54e49f9ed82e22f1011bb4e9e4f4b8a641f"
    startupapicheck = "sha256:1c519d4afca1413d1e4ccd78bdc756184418ab55a34569a3b3de39d32f9974e1"
    acmesolver      = "sha256:c8c1225bb2fe8ab37a330b77f0d8c2ee6a41210fcb54fc07ca606ab9a022b8b7"
  }
  images = {
    for component, digest in local.image_digests : component => {
      repository = "quay.io/jetstack/cert-manager-${component}"
      tag        = "v1.21.3"
      digest     = digest
    }
  }
  controller_values = {
    crds                     = { enabled = true, keep = true }
    config                   = { gatewayAPI = { enabled = true } }
    clusterResourceNamespace = var.namespace
    global                   = { leaderElection = { namespace = var.namespace } }
    image                    = local.images.controller
    webhook                  = { image = local.images.webhook }
    cainjector               = { image = local.images.cainjector }
    startupapicheck          = { image = local.images.startupapicheck }
    acmesolver               = { image = local.images.acmesolver }
  }
  issuer_id = substr(sha256(var.issuer.name), 0, 24)
  issuer_object = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = var.issuer.name }
    spec = {
      acme = {
        email               = var.issuer.acme_email
        server              = var.issuer.acme_server
        privateKeySecretRef = { name = "cm-acme-${local.issuer_id}" }
        solvers = [{
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = var.issuer.dns01.credential_secret_name
                key  = var.issuer.dns01.credential_secret_key
              }
            }
          }
        }]
      }
    }
  }
}

resource "helm_release" "controller" {
  name             = "cert-manager"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_version
  wait             = true
  wait_for_jobs    = true
  timeout          = 600
  values           = concat([jsonencode(local.controller_values)], var.extra_helm_values)
}

resource "helm_release" "configuration" {
  name          = "cm-issuer-${local.issuer_id}"
  namespace     = var.namespace
  chart         = "${path.module}/chart"
  wait          = true
  wait_for_jobs = true
  timeout       = 600
  values        = [jsonencode({ issuer = local.issuer_object })]

  depends_on = [helm_release.controller]
}
