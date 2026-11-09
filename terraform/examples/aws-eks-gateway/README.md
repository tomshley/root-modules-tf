# AWS gateway

Run the CRD bootstrap in [k8s-gateway](../../modules/k8s-gateway/README.md) first. Configure the Helm and Kubernetes providers for your cluster. Create namespace `gateway-system` and an existing TLS Secret named `public-example-tls` there before applying; its certificate must cover the synthetic `login.example.test` hostname. Use the provider-managed Gateway API variant where applicable.

This example creates no routes, application workloads, cloud resources or credentials. It is independent of association-file and identity modules.
