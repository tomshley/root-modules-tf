# AWS EKS gateway attachments

This module adds load-balancer attachments to `k8s-gateway` as Service annotations. It creates no cloud resources and declares no routing, TLS-policy or application input.

Every [base input and output](../k8s-gateway/README.md) is preserved. Bootstrap
CRDs as documented there before applying. TLS terminates at the gateway.
The AWS Load Balancer Controller must already be installed with the necessary
cloud permissions. This shim selects its external NLB Service integration.

Optional attachment inputs default to null and omit their annotation:
`nlb_scheme` (`internet-facing` or `internal`), `nlb_eip_allocations`
(list of EIP allocation identifiers), `nlb_cross_zone` (bool),
`nlb_target_type` (`instance` or `ip`), `nlb_additional_resource_tags`
and `tags` (maps). Specific NLB tags win duplicate keys from `tags`.
Typed attachment annotations win conflicting `service_annotations` entries.
When `nlb_cross_zone` is set, existing load-balancer attributes are split on
commas, trimmed, and empty entries or existing `load_balancing.cross_zone.enabled`
entries are removed before appending the typed cross-zone value. Other attributes
are preserved. When it is null, the caller's attributes annotation is untouched.
A null `nlb_scheme` leaves the controller's internal default; public attachment
requires `nlb_scheme = "internet-facing"`. EIP allocations require that explicit
internet-facing scheme and must match the controller-selected subnets.
When non-null, the list must be non-empty and each entry must match
`^eipalloc-[0-9a-f]+$`.
Tag keys must be non-empty after trimming, with no leading or trailing whitespace,
`,` or `=`. Values must be non-null and must not contain `,`; `=` is allowed
because the AWS Load Balancer Controller splits each tag entry on its first `=`.
Both tag maps limit keys to 128 characters and values to 256 characters, and
reject keys starting with `aws:` case-insensitively.

See the [gateway-only example](../../examples/aws-eks-gateway).

## References

- [Gateway API specification](https://gateway-api.sigs.k8s.io/references/spec/)
- [Gateway API implementations and conformance](https://gateway-api.sigs.k8s.io/implementations/)
- [Service annotation reference](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/)
