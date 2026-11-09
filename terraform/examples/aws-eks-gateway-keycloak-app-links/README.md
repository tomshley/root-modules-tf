# EKS Gateway, Keycloak and app links

Composes the AWS Gateway attachment shim, cert-manager, the Keycloak shim, app-link rendering and a static responder on an existing cluster. The consumer owns both HTTPRoutes and the DNS record. Existing direct LoadBalancer Keycloak examples are unchanged.

## Prerequisites

- An existing EKS cluster and kubeconfig, Gateway API CRDs installed before cert-manager starts, and the AWS Load Balancer Controller.
- Envoy Gateway CRDs, including `EnvoyProxy` and `ClientTrafficPolicy`, bootstrapped before applying the Gateway module. Follow the [k8s-gateway CRD prerequisite and ownership instructions](../../modules/k8s-gateway/README.md#crd-prerequisite-and-ownership); the controller module does not install them.
- An existing PostgreSQL database at `db_endpoint`; this example does not provision a cluster, database or credentials.
- A Cloudflare API-token Secret named `cloudflare-dns01` in the pre-created `cert-manager` namespace. Set the Cloudflare provider's credentials through its environment, not Terraform variables.
- Existing `keycloak-admin` and `keycloak-db` Secrets in the pre-created `identity` namespace. Their keys are `admin-password`, `db-user` and `db-password`. The empty `db_user` argument is unused: the username comes from the existing Secret.
- Replace the synthetic `public_hostname`, `zone_id`, cluster and database inputs before applying. The default reserved domain and synthetic fingerprint are illustrative, not issuance or application credentials.

Configure the providers through `kube_config_path`, the AWS provider's normal credential chain and the Cloudflare provider environment. Run `tofu init`, `tofu plan`, then review the plan before applying. DNS is an unproxied CNAME whose target comes only from the Gateway output; the baseline module also configures the zone's TLS settings.

## Consumer contract

`public_hostname` has one declaration and its literal appears only in `variables.tf`. Every listener, route, Keycloak URL and redirect URI derives from it. Service names, ports, parent references, namespaces, issuer references, app-link files and DNS targets are wired through module outputs.

There is one synthetic `realm/realm.json`, with no passwords or client secret. Its public callback origin uses keycloak-config-cli's documented `$(env:PUBLIC_ORIGIN)` substitution. The example evaluates that same substitution for the two plan-time checks and supplies the same origin and substitution flag to the import Job. Thus the one realm file works for any hostname without repeating a hostname literal or generating a second realm file. Both check blocks are consumer policy; Terraform check failures are warnings during ordinary planning, so inspect them before applying. The test command treats assertion failures as failures.

The well-known HTTPRoute uses Exact matches from `module.app_links.paths`; the Keycloak route uses `PathPrefix /`. Both attach to the Gateway's exported name and namespace. All backends share the Gateway namespace, so no cross-namespace ReferenceGrant is needed. Exact paths take precedence over the catch-all prefix. Keycloak receives `proxyHeaders = "xforwarded"` for TLS termination at the Gateway; keep its ClusterIP Service reachable only through trusted proxies and authorized cluster workloads.

DNS-01 can issue before this Gateway serves traffic. Envoy's first readiness wait is bounded by the Gateway module's timeout and requires the certificate Secret; load-balancer outputs remain null until a proxy Service/address exists. A pending external address can require a later refresh/apply before publishing DNS. The issuer does not depend on that DNS record or on HTTP-01 traffic.

## Validation

The contract target plans this complete example with mocked providers, then renders the actual local Gateway chart using its planned values through the real Helm provider. It compares the listener and both planned HTTPRoute manifests with the exported contracts, and a mutated route must fail. CI has no cluster and performs plan/render validation, not a live apply or certificate issuance. Real planning requires the pre-installed Gateway API CRDs because consumer-owned `kubernetes_manifest` resources use Kubernetes schema discovery.

## Self-hosted variant

Use `../../modules/k8s-gateway` instead of the cloud attachment shim, retaining the same listeners, routes and output wiring:

```hcl
module "gateway" {
  source        = "../../modules/k8s-gateway"
  name          = "public-gateway"
  namespace     = "identity"
  chart_version = "v1.9.3"
  service_type  = "LoadBalancer"
  listeners = {
    auth = {
      hostname   = var.public_hostname
      tls_issuer = { name = module.cert_manager.issuer_name }
    }
  }
}
```

Supply MetalLB or kube-vip for `LoadBalancer`, or use `service_type = "NodePort"` behind the cluster's edge and publish DNS for that edge instead of expecting a load-balancer output. Replace the cloud Keycloak shim with `k8s-keycloak`, retaining the same existing Secret references and public hostname. These provider-neutral variants are documentation examples; the offline tests exercise the two cloud compositions.

## References

- [Gateway API HTTP routing and match precedence](https://gateway-api.sigs.k8s.io/api-types/httproute/)
- [cert-manager Gateway usage and CRD ordering](https://cert-manager.io/docs/usage/gateway/)
- [keycloak-config-cli variable substitution](https://github.com/adorsys/keycloak-config-cli/blob/v6.2.1/README.md#variable-substitution)
- [Keycloak reverse proxy configuration](https://www.keycloak.org/server/reverseproxy)
