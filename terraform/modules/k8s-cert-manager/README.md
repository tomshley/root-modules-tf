# Kubernetes cert-manager

Installs the official cert-manager Helm chart with Gateway API support and exactly one ACME `ClusterIssuer` using Cloudflare DNS-01. This is optional infrastructure: a Gateway can use a consumer-supplied TLS Secret without this module. No Gateway module or cloud provider is required here.

## Usage

```hcl
module "cert_manager" {
  source        = "../modules/k8s-cert-manager"
  chart_version = "v1.21.3"

  issuer = {
    name       = "public-acme"
    acme_email = "platform@example.test"
    dns01 = {
      provider               = "cloudflare"
      credential_secret_name = "cloudflare-api-token"
    }
  }
}
```

Configure the Helm provider in the caller. Install at most one cert-manager controller per cluster; this module uses the release name `cert-manager`. Installation requires cluster-level permissions for cert-manager's CRDs and RBAC. The controller and issuer releases each have a 600-second Helm timeout and wait for workloads and hook Jobs. The issuer release is explicitly ordered after the controller release, including its startup API check.

## Prerequisites and ownership

- **Gateway API CRDs are platform-owned.** Install them before cert-manager starts; this module never installs them or references a Gateway. Official guidance requires restarting cert-manager if those CRDs are installed later. Wire the caller's dependency explicitly rather than relying on timing.
- **cert-manager CRDs are chart-owned.** Following the official Helm installation instructions, generated values set `crds.enabled = true`. They also explicitly set `crds.keep = true`: Helm retains these CRDs on uninstall. Retained CRDs and their remaining custom resources require a separate, deliberate cleanup; do not delete the CRDs while certificates or issuers still depend on them.
- **DNS credentials are consumer-owned.** An existing Secret containing a Cloudflare API token must be in `namespace`, cert-manager's explicit cluster resource namespace. This module neither creates nor reads that Secret. For a new namespace, arrange Secret creation before cert-manager needs to solve a challenge, or use a pre-created namespace with `create_namespace = false`. Use the least-privilege token permissions described in the official Cloudflare documentation.
- **The sole custom resource created here is one `ClusterIssuer`.** A small local Helm chart installs it after cert-manager, avoiding a plan-time CRD schema lookup. There is no `kubernetes_manifest`, Certificate, Gateway, or credential Secret resource. cert-manager creates its ACME account private-key Secret, named `cm-acme-` plus the first 24 hexadecimal characters of the issuer name's SHA-256 hash, in `namespace`. This is distinct from the supplied DNS credential Secret.
- **ACME account private-key Secrets are retained.** cert-manager v1.21.3 creates them without an `ownerReference`, so deleting the ClusterIssuer does not garbage-collect its Secret. Changing `issuer.name` changes the derived Secret name, creates a new private key and ACME account, and leaves the previous Secret behind. Account-key Secrets also survive uninstall. Like retained CRDs and the Helm-created namespace, these leftovers require deliberate cleanup; preserve any account key still needed by an active issuer or ACME account.
- **Certificate requests and attachment are consumer-owned.** This module creates no Certificate objects, waits for no certificate issuance, and makes no readiness claim for the issuer. Consumers may explicitly create Certificates or annotate their own Gateway objects, using the issuer outputs. DNS-01 does not require a Gateway serving challenge traffic.

## Inputs

| Input | Type | Default | Contract |
|---|---|---|---|
| `namespace` | `string` | `"cert-manager"` | Non-null DNS-1123 label, at most 63 characters. |
| `create_namespace` | `bool` | `true` | Non-null; lets Helm create the namespace on installation. Helm does not remove that namespace on uninstall. |
| `chart_version` | `string` | Required | Exactly `"v1.21.3"`; the supported chart and image digests advance together. Floating or other versions are rejected. |
| `issuer` | `object` | Required | Non-null; fields below. |
| `extra_helm_values` | `list(string)` | `[]` | Non-null YAML mappings, appended in order after generated controller values. Later values win. Applies only to the upstream controller chart, not the issuer chart. |

`issuer` has this shape:

```hcl
object({
  name        = string
  acme_email  = string
  acme_server = optional(string, "https://acme-v02.api.letsencrypt.org/directory")
  dns01 = object({
    provider               = string
    credential_secret_name = string
    credential_secret_key  = optional(string, "api-token")
  })
})
```

Required nested fields must be non-null. `name` is a DNS-1123 label of at most 63 characters. `acme_email` supports an ASCII dot-atom subset: each non-empty atom contains only letters, digits, underscores, plus signs or hyphens, and dots separate atoms. The local part is at most 64 characters, with at most 254 characters overall and a dotted DNS domain. Leading, trailing or consecutive dots, quoted local parts, comments, display names, non-ASCII local parts, other punctuation, whitespace and control characters are not supported. This conservative subset also avoids URI delimiters because cert-manager inserts the address directly into a `mailto:` contact. `acme_server` must be an HTTPS URL with a DNS hostname, optional port from 1 to 65535, and no credentials, whitespace, control characters or fragment. Every percent escape must have exactly two hexadecimal digits, in both the path and query. DNS labels in both the server hostname and email domain must contain 1–63 characters, and their last label must not be all numeric; IP literals are not supported. The default is the production Let's Encrypt directory; supply the staging directory when testing issuance.

`dns01` must be non-null, and `provider` must be `"cloudflare"`. `credential_secret_name` is a DNS-1123 subdomain, at most 253 characters with labels of at most 63 characters. Its name must not be `cert-manager-webhook-ca`, which the pinned webhook manages, and must differ from the generated ACME account-key Secret name described above; both Secrets occupy `namespace`, so a collision fails at plan time. `credential_secret_key` is 1–253 ASCII letters, digits, dots, underscores or hyphens; a single dot or a prefix of two dots is forbidden by Kubernetes key validation. As specified by Terraform's non-null optional defaults, explicit null for `acme_server` or `credential_secret_key` selects its default.

The rendered solver is:

```yaml
solvers:
  - dns01:
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-api-token
          key: api-token
```

Caller overrides can replace any generated controller value, including Gateway API support, CRD settings and images; the caller owns the consequences. No override is merged into the issuer object. Leader election is explicitly scoped to `namespace`, rather than the chart's default `kube-system` namespace.

## Outputs

| Output | Meaning |
|---|---|
| `issuer_name` | Configured ClusterIssuer name, ordered after its release installation. |
| `issuer_kind` | Always `"ClusterIssuer"`, ordered after its release installation. |
| `namespace` | Controller release namespace and DNS credential Secret namespace. |
| `release_status` | cert-manager controller Helm release status; not issuer or certificate readiness. |

## Version and image pins

The official Jetstack chart is pinned to `v1.21.3` (`https://charts.jetstack.io`). For this version, Gateway API support is enabled using **`config.gatewayAPI.enabled = true`**, not the older `config.enableGatewayAPI` setting. The pinned chart's values document the new configuration shape.

All five images use the official `quay.io/jetstack/cert-manager-<component>` repositories and tag `v1.21.3`, with the registry manifest digests below. The digest, not the tag, selects the pulled image. The ACME HTTP-01 solver is pinned even though this issuer uses DNS-01.

| Component | Manifest digest |
|---|---|
| controller | `sha256:9f4f96a33c7774cef24466fcd85031997531a03a8d117f151126baa8d1290dcc` |
| webhook | `sha256:055ac8e9de6a0ba6763794838fe38944acc650f68ebe1b01dd8be079e580f458` |
| cainjector | `sha256:083d0e906f8eb44e255fe4ff817ae54e49f9ed82e22f1011bb4e9e4f4b8a641f` |
| startupapicheck | `sha256:1c519d4afca1413d1e4ccd78bdc756184418ab55a34569a3b3de39d32f9974e1` |
| acmesolver | `sha256:c8c1225bb2fe8ab37a330b77f0d8c2ee6a41210fcb54fc07ca606ab9a022b8b7` |

The local issuer Helm release uses a stable `cm-issuer-` prefix plus the same 24-character hash, so even maximum-length issuer names cannot overflow Helm release-name limits.

## References

- [RFC 5322 dot-atom syntax](https://www.rfc-editor.org/rfc/rfc5322#section-3.2.3)
- [RFC 5321 mailbox size limits](https://www.rfc-editor.org/rfc/rfc5321#section-4.5.3.1)
- [Official Helm installation and CRD lifecycle](https://cert-manager.io/docs/installation/helm/)
- [Gateway usage and CRD ordering](https://cert-manager.io/docs/usage/gateway/)
- [Cloudflare DNS-01 API token configuration](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [ClusterIssuer credential namespace and ACME configuration](https://cert-manager.io/docs/configuration/acme/)
- [Pinned ACME account-key Secret creation](https://github.com/cert-manager/cert-manager/blob/v1.21.3/pkg/issuer/acme/setup.go#L594-L615)
- [Pinned chart values and Gateway API configuration](https://github.com/cert-manager/cert-manager/blob/v1.21.3/deploy/charts/cert-manager/values.yaml)
- [Official image registry](https://quay.io/organization/jetstack/)
- [Kubernetes Secret key validation](https://github.com/kubernetes/apimachinery/blob/v0.30.0/pkg/util/validation/validation.go)
