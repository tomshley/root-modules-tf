# k8s-static-responder

Serves caller-supplied strings verbatim at exact URL paths. Owns one ConfigMap,
Deployment, ClusterIP Service and PodDisruptionBudget in an existing namespace.
No content templating, proxying, remote fetching, namespace creation, TLS, DNS,
public exposure or route objects. The consumer owns all of those concerns.

Requires hashicorp/kubernetes **2.9.0 or later** (within major version 2) for
the pod security context's `seccomp_profile` attribute
([#1617](https://github.com/hashicorp/terraform-provider-kubernetes/pull/1617)).
See the provider
[2.9.0 changelog](https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.9.0/CHANGELOG.md).
The contract suite initializes, validates and plans with the exact declared
minimum provider version to catch attributes that require a newer release.

## Inputs

| Input | Type | Default |
|---|---|---|
| `name`, `namespace` | `string` | required |
| `files` | `map(object({ content = string, content_type = string }))` | required |
| `image` | `string` | required, SHA-256 digest-pinned |
| `replicas` | `number` | `2` |
| `pdb_min_available` | `number` | `1` |
| `service_port` | `number` | `80` |
| `resources_requests_cpu`, `resources_requests_memory` | `string` | `null` |
| `resources_limits_cpu`, `resources_limits_memory` | `string` | `null` |
| `labels` | `map(string)` | `{}` |

`name` must be a DNS-1035 label (starting with a letter); `namespace` must be
a DNS-1123 label. Both are limited to 63 characters. All four resource names
use `name` unchanged, without suffixes.

File keys begin with `/` and cannot contain `?`, `#` or `*`.
They must not contain `//`, `/./`, `/../`, a trailing `/.` or `/..`, or `%`,
which nginx normalizes before matching.
File keys must not end with `/`, including `/` itself, and must not contain
Unicode Cc control characters (U+0000–U+001F or U+007F–U+009F).
Replicas must be positive integers; PDB minimum availability must be a non-negative
integer smaller than replicas. The defaults remain two replicas and minimum one.
Setting `replicas = 1` requires `pdb_min_available = 0`.
The Service port must be an integer from 1 to 65535.
Explicit null selects the default for `replicas`, `pdb_min_available` and
`service_port`.
Content must be non-null. Content types must be non-empty printable ASCII
(U+0020–U+007E), with no leading or trailing ASCII space. Internal spaces are
allowed; Unicode and control characters, including those at either edge, are
rejected by the printable-ASCII rule. One validation reports one diagnostic for
the first offending file in lexical path order: null, empty or space-only types
report the non-empty message; otherwise non-printable characters take precedence
over leading or trailing ASCII space.
Empty `files = {}` is valid and serves only 404 responses.

The serialized files and complete ConfigMap data, including generated configuration,
are each bounded at **900 KiB (921,600 bytes)**. The check uses base64 length
(maximum 1,228,800 characters) to bound UTF-8 bytes conservatively. This leaves
124 KiB below Kubernetes' 1 MiB ConfigMap limit for metadata and overhead, and
prevents large sets of paths from hiding excessive generated configuration.

Every entry becomes an nginx `location =` with its own content type. Content is
stored under hashed ConfigMap keys, not interpreted as filesystem paths. nginx
percent-decodes the request path before RFC 3986 dot-segment normalization and
exact matching. Percent-encoded equivalents of configured paths, including
encoded slashes (`%2F`), are served; the query string is ignored.
Slash merging is disabled, so duplicated-slash variants of configured
paths return 404. Other paths return
404. Server version tokens are disabled. nginx listens on IPv4 only, on port
8080; no unconditional IPv6 socket is opened on nodes where IPv6 may be disabled.
Readiness and liveness use TCP on 8080, without reserving a public health path.
The Service maps its configured port to that container port.

The pod runs as UID/GID 101, non-root, with RuntimeDefault seccomp, a read-only
root filesystem, no privilege escalation, all capabilities dropped and no
service-account token. Service-link environment injection is disabled.
Only a memory-backed `/tmp`, capped at 16 MiB, is writable.
A pod-template `checksum/files` annotation covers the full ConfigMap data,
including generated nginx configuration, content and content types; template or
content changes roll pods.
Selector labels are reserved and cannot be overridden by `labels`.
The contract suite runs `nginx -t` and serves both fixed and escaped-input fixtures
to check exact paths, bytes and Content-Type, plus duplicated-slash rejection
when nginx is on `PATH`; otherwise it prints an explicit skip notice.

## Image

There is deliberately no Terraform default: the consumer supplies `image`.
The current recommended default, verified from Docker Hub's `stable-alpine`
multi-platform manifest on 2026-11-06, is:

```hcl
image = "nginxinc/nginx-unprivileged@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"
```

The registry's `Docker-Content-Digest` matched SHA-256 of the returned manifest
bytes, including Linux amd64 and arm64 manifests. Review and update the pin
deliberately; tags are mutable. The image must provide nginx on port 8080 and
support UID/GID 101. See https://github.com/nginx/docker-nginx-unprivileged and
https://kubernetes.io/docs/concepts/configuration/configmap/.

## Outputs

- `service_name`: created Service name.
- `service_port`: configured Service port.
- `paths`: sorted keys of `files`, for consumer-owned exact matches.
