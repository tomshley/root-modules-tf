# GCP GKE gateway attachments

This module adds load-balancer attachments to `k8s-gateway` as Service annotations. It creates no cloud resources and declares no routing, TLS-policy or application input.

Every [base input and output](../k8s-gateway/README.md) is preserved. Use its
provider-managed Gateway API CRD bootstrap variant on applicable GKE clusters.
TLS terminates at the gateway.

Optional `load_balancer_ip` and `internal` default to null. The former names an
existing reserved **address resource**, not an IP literal: GKE's annotation
`networking.gke.io/load-balancer-ip-addresses` takes resource names and requires
a supporting GKE version/configuration (GKE 1.29+). A reserved address requires
`internal = true` and GKE subsetting. Subsetting is enabled by default from
GKE 1.36; enable it explicitly on older clusters. GKE ignores this annotation
on external Services without `loadBalancerClass`, which this module does not
configure. `internal` selects internal
or external attachment. Explicit `false` removes the internal attachment
annotations (`networking.gke.io/load-balancer-type` and the deprecated
`cloud.google.com/load-balancer-type`), including conflicting raw annotations.
Null preserves both raw annotations. The module does not emit an
unsupported `External` annotation value. Base `labels` is mirrored unchanged and labels the
proxy Service and Kubernetes objects; it is not an extra cloud-label input.
Typed attachment annotations win conflicting `service_annotations` entries.
No address reservation or DNS record is created.

See the [gateway-only example](../../examples/gcp-gke-gateway).

## References

- [Gateway API specification](https://gateway-api.sigs.k8s.io/references/spec/)
- [Gateway API implementations and conformance](https://gateway-api.sigs.k8s.io/implementations/)
- [GKE Service parameters](https://cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer-parameters)
