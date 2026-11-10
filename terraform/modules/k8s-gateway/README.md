# Kubernetes gateway

Installs the official Envoy Gateway controller chart **v1.9.3** and creates one
GatewayClass, one Gateway, its EnvoyProxy configuration and a TLS 1.2
ClientTrafficPolicy. It creates no routes, DNS records, cloud resources or
applications. Consumers own routes and backend Services.

## CRD prerequisite and ownership

The cluster owner must bootstrap CRDs **before applying this module**. The
controller release sets both `skip_crds = true` and `crds.enabled = false`.
There is no custom CRD packaging or implicit adoption of provider-owned schemas.

The exact bootstrap pipeline from the
[versioned installation guide](https://raw.githubusercontent.com/envoyproxy/gateway/v1.9.3/site/content/en/v1.9/install/install-helm.md),
with its version placeholder resolved, is:

```sh
helm template eg oci://docker.io/envoyproxy/gateway-crds-helm \
  --version v1.9.3 \
  --set crds.gatewayAPI.enabled=true \
  --set crds.gatewayAPI.channel=standard \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side -f -
```

For GKE or another provider managing compatible Gateway API CRDs, retain the
provider as their owner and install **only** Envoy Gateway CRDs:

```sh
helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm \
  --version v1.9.3 \
  --set crds.gatewayAPI.enabled=false \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side -f -
```

Check the provider's Gateway API version/channel against Envoy Gateway's
[compatibility matrix](https://gateway.envoyproxy.io/news/releases/matrix/).
The published v1.9.3 bundle is Gateway API v1.6.1. Experimental APIs require the
appropriate channel if the consumer needs them.

The standalone CRD chart is intentionally rendered and server-side applied:
the guide documents Helm's size limit for large CRDs under `templates/`.
The controller chart's `crds/` installation mechanism does not upgrade CRDs.
Before a controller upgrade, the cluster owner must review the new release's
compatibility/upgrade notes, upgrade provider-owned schemas through that
provider, and server-side apply the matching Envoy schemas using the pipeline
above. Do not delete/recreate schemas: that deletes their custom resources.
Uninstalling this module does not uninstall CRDs.

Configuration objects are rendered through a small local Helm chart, **not**
`kubernetes_manifest`. A plan therefore does not need CRD discovery; apply does.
The configuration release waits for the Gateway's Programmed condition through
a digest-pinned, least-privilege hook Job before reading its generated Service.
Existing TLS Secrets must exist at apply time. Issuer-based TLS additionally
requires a working consumer-installed cert-manager with Gateway support; this
module has no cert-manager dependency and creates no Certificates.

When all listeners await issuer-backed certificate Secrets, Envoy Gateway creates
no proxy Deployment or Service until a Secret makes a listener valid
([missing-certificate behavior](https://github.com/envoyproxy/gateway/issues/3044)).
The first apply's readiness hook waits for issuance within
`max(1, helm_timeout - 30)` seconds, and `load_balancer_*` outputs stay null until
the proxy Service has an assigned address (they may be unknown in plans while
the Service read is deferred). The issuer must be able to complete without this
Gateway serving traffic, for example using DNS-01.

## Inputs

| Input | Default |
|---|---|
| `name`, `namespace` | required strings |
| `chart_version` | required; `v1.9.3` |
| `listeners` | required map, non-empty |
| `create_namespace` | `false` |
| `service_type` | `"LoadBalancer"`; alternatively `"NodePort"` |
| `service_annotations`, `labels` | `{}` |
| `replicas`, `pdb_min_available` | `2`, `1` |
| `resources_requests_cpu`, `resources_requests_memory` | `null` |
| `resources_limits_cpu`, `resources_limits_memory` | `null` |
| `network_policy_enabled` | `false` |
| `helm_timeout` | `600` seconds, integer minimum `2` |
| `extra_helm_values` | `[]`; appended last to controller values |

The controller Helm release name is `eg-controller-<20-character hash>` of
namespace/name, within Helm's 53-character limit. Its release-derived cluster-scoped
RBAC, controller identity and GatewayClass are isolated across namespaces,
including instances with the same `name`.
The proxy Service is named `<name>-proxy`, avoiding the controller chart's
fixed `envoy-gateway` Service name.
Use a dedicated namespace per module instance: the official controller chart
uses fixed controller resource names within its namespace.

`name` must be a DNS-1035 label (starting with a lowercase letter), at most
53 characters; this keeps `<name>-proxy` within the Service name limit of 63.
`listeners` must contain 1–64 entries. Each listener has `hostname`;
optional `port = 443`, `protocol = "HTTPS"`
(`HTTP` and passthrough `TLS` are supported), `tls_secret_name` or
`tls_issuer = { name, kind = "ClusterIssuer" }`, and
`allowed_route_namespaces = "Same"` (`All` or `Selector` also accepted).
`Selector` requires a non-empty `allowed_route_selector` map of namespace labels.
Other namespace modes must omit that selector.

HTTPS requires exactly one TLS source. All issuer-backed listeners must name
the same issuer and kind. If any listener uses an issuer, every HTTPS listener
must use that issuer; mixing issuer-backed and existing-Secret HTTPS listeners
is rejected because the annotation covers the whole Gateway and cert-manager
could overwrite operator-managed Secrets. `ClusterIssuer` emits only
`cert-manager.io/cluster-issuer`; `Issuer` emits only `cert-manager.io/issuer`.
Issuer-backed listeners reference the deterministic Secret
`<name>-<listener>-tls`. Gateways using only existing Secrets emit no issuer annotation.
IP literals are rejected. Hostnames accept DNS names and Gateway API wildcard DNS names; listener names
must be DNS labels. Port/protocol/hostname combinations must be unique, and all
listeners on a shared port must use the same protocol.
TLS Secret and issuer names must be DNS-1123 subdomains of at most 253
characters, without surrounding whitespace. Selector and metadata label keys
use Kubernetes qualified names (optional DNS prefix up to 253 characters and
name up to 63); label values may be empty or valid label values up to 63
characters. Service annotation keys follow the same qualified-name rules, case-insensitively
as in [Kubernetes validation](https://github.com/kubernetes/apimachinery/blob/v0.30.0/pkg/api/validation/objectmeta.go#L44-L52);
annotation values remain unrestricted. Resource requests and limits accept
nonnegative Kubernetes Quantity syntax, including decimal SI, binary SI and
exponent forms. A request must not exceed its corresponding limit when both
are set; comparisons normalize units, nano precision and BinarySI saturation.
Caller labels cannot use Envoy's selector/ownership keys, `app.kubernetes.io/part-of`
or `gateway-instance`. The controller chart also reserves `app.kubernetes.io/instance`,
`app.kubernetes.io/version`, `helm.sh/chart` and `control-plane`.
`gateway-instance` is proxy-only and can never label the readiness Job. Envoy's own
`component=proxy` selector is not overridden; see the pinned
[selector and pod-label source](https://github.com/envoyproxy/gateway/blob/v1.9.3/internal/infrastructure/kubernetes/proxy/resource_provider.go#L466-L538)
and [reserved application labels](https://github.com/envoyproxy/gateway/blob/v1.9.3/internal/infrastructure/kubernetes/proxy/resource.go#L52-L59).
Invalid inputs fail at plan time.

The pinned v1.9.3 maps privileged listener ports 1–1023 to pod ports by adding
10000 (80 → 10080, 443 → 10443). Different listener ports must not collide
after this translation. Ports 19000–19003 are reserved for the proxy admin,
stats, shutdown manager and readiness endpoints and cannot be listeners. See
the [v1.9.3 port translation source](https://github.com/envoyproxy/gateway/blob/v1.9.3/internal/gatewayapi/listener.go#L1431-L1455)
and [documented open ports](https://github.com/envoyproxy/gateway/blob/v1.9.3/site/content/en/v1.9/boilerplates/open-ports.md).

## Workload defaults and optional network policy

The TLS 1.2 minimum ClientTrafficPolicy and non-root/capability/seccomp
hardening are fixed defaults with no opt-out inputs. Only the PDB can be
relaxed, by setting `pdb_min_available = 0`.
Listeners with `protocol = "HTTP"` and no TLS inputs are supported, for example
in non-production environments; the TLS 1.2 minimum policy only affects TLS handshakes.

The proxy has two replicas, a PDB, native readiness/liveness/startup probes,
non-root UID/GID 65532, no privilege escalation,
dropped capabilities and RuntimeDefault seccomp. Controller, proxy, shutdown
manager and readiness Job images are digest-pinned. The controller's own PDB
also keeps one of its two replicas available.
The proxy keeps the upstream writable-root default for logs and UDS sockets ([v1.9.3 source](https://github.com/envoyproxy/gateway/blob/v1.9.3/internal/infrastructure/kubernetes/proxy/resource.go#L525-L526)).
The readiness Job deadline and kubectl timeout are `max(1, helm_timeout - 30)`
seconds, so the Job expires before Helm does, including at the two-second minimum.

With `network_policy_enabled = true`, proxy pods may receive traffic only on
the listener ports. Unprivileged Envoy maps listener ports below 1024 to pod
ports 10000 higher; the policy permits those actual target ports. Egress is
allowed only to DNS, the Envoy Gateway controller (xDS), and pods in the
namespaces selected by the listeners' allowed-route-namespaces inputs.
`Same` selects the Gateway namespace; `Selector` selects matching namespaces.
Gateway API backends live in the route's namespace unless a ReferenceGrant is
used, so this namespace set is the honest, input-free bound on route backends.
A ReferenceGrant to another namespace needs that namespace added to the allowed
namespace selector. `All` cannot bound egress and fails validation with the policy.

DNS rules target standard kube-system pods labelled `k8s-app=kube-dns` on
TCP/UDP 53; xDS targets this controller on TCP 18000. Nonstandard/NodeLocal DNS
needs consumer-managed policy instead. Kubernetes policies are additive; another
policy selecting these pods can widen access. Enforcement requires a compatible
cluster network implementation. Resource requests/limits apply to the main proxy
container; the shutdown manager retains upstream resources.
With all resource inputs null, the proxy retains upstream requests of `100m`
CPU and `512Mi` memory. Setting any resource input overrides upstream resources;
only the supplied requests and limits are emitted.

`extra_helm_values` is the unchanged controller escape hatch, not a route API.
Overrides must preserve disabled CRDs, compatible pinned images, controller
identity and xDS ports/labels when using this module's NetworkPolicy.

## Outputs

`gateway_name`, `gateway_namespace`, `gateway_class_name`, `service_name`,
`listener_names`, `load_balancer_hostname`, `load_balancer_ip`.
Addresses come from Service status. NodePort returns null addresses;
hostname-only load balancers return null IP. A pending allocation may be null
until the next refresh. Multiple addresses return the first non-empty value.

See the gateway-only [AWS](../../examples/aws-eks-gateway) and
[GCP](../../examples/gcp-gke-gateway) examples.

## References

- [Official installation](https://gateway.envoyproxy.io/docs/install/install-helm/)
- [EnvoyProxy API](https://gateway.envoyproxy.io/v1.9/api/extension_types/#envoyproxy)
- [Gateway API specification](https://gateway-api.sigs.k8s.io/references/spec/)
- [Gateway API implementations and conformance](https://gateway-api.sigs.k8s.io/implementations/)
- [cert-manager Gateway annotations](https://cert-manager.io/docs/usage/gateway/)
