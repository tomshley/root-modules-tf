# gcp-keycloak

Forwards Keycloak deployment inputs and outputs through `k8s-keycloak`.

## Public hostname and existing Secrets

| Input | Type | Default | Behaviour |
|---|---|---|---|
| `public_hostname` | `string` | `null` | When set, emits `extraEnvVars` with `KC_HOSTNAME=https://<host>`. Null emits nothing. |
| `existing_secrets` | Object below | `null` | References existing Kubernetes Secrets instead of creating credentials Secrets. |

```hcl
existing_secrets = object({
  admin = optional(object({
    name         = string
    password_key = optional(string, "admin-password")
  }))
  db = optional(object({
    name         = string
    user_key     = optional(string, "db-user")
    password_key = optional(string, "db-password")
  }))
})
```

Each credential is independent: `admin` maps to `auth.existingSecret` and
`auth.passwordSecretKey`; `db` maps to `externalDatabase.existingSecret`,
`externalDatabase.existingSecretUserKey`, and `externalDatabase.existingSecretPasswordKey`.
The consumer supplies these Secrets in the Keycloak namespace. Secret names must
be DNS-1123 subdomains of at most 253 characters. Secret keys must be non-empty,
at most 253 characters, and match `^[-._a-zA-Z0-9]+$`; they must not be `.`, `..`,
or begin with `..`. `public_hostname` must be a bare lowercase DNS name with a
letter in the last label and no scheme, path, port or whitespace; IP literals
are rejected.
When `existing_secrets.db` is set, the Secret's user key supersedes `db_user`.
`existing_secrets.admin` and `admin_password` are mutually exclusive;
`existing_secrets.db` and `db_password` are mutually exclusive.
An existing Secret removes the requirement for that credential's password or Secret Manager ID,
skips cloud credential lookup and creation of its Kubernetes Secret, and leaves the other credential unchanged.
With null inputs, existing password handling and rendered Helm values are unchanged.

With `public_hostname` set, every `extra_helm_values` entry must decode as a
single YAML document; malformed or multi-document YAML fails at plan time.
The YAML strings in `extra_helm_values` remain last and win on overlap, except
that setting top-level `extraEnvVars` with `public_hostname` fails at plan time:
Helm replaces lists, so that override would silently discard `KC_HOSTNAME`.
Other overrides, including Secret references, retain their existing precedence.
`public_hostname` does not configure TLS or exposure. Do not combine it with
`ingress.hostname` or `adminIngress.hostname` in `extra_helm_values`: chart 24.4.2
emits `KEYCLOAK_HOSTNAME` from a non-empty `ingress.hostname` when
`ingress.enabled` is true, and `KEYCLOAK_HOSTNAME_ADMIN` from a non-empty
`adminIngress.hostname` when `adminIngress.enabled` is true. Both also require
`proxyHeaders` to be empty and can appear alongside the module's `KC_HOSTNAME`
entry.

Migration: Bitnami Keycloak chart 24.4.2 does not read a top-level `hostname`
in `extra_helm_values`; use `public_hostname` instead. Keycloak 26 hostname v2
supports a full URL to fix the public HTTPS scheme and port; see the
[hostname v2 guide](https://www.keycloak.org/server/hostname) and its
[Keycloak 26 source](https://github.com/keycloak/keycloak/blob/26.0.8/docs/guides/server/hostname.adoc).

| Output | Value |
|---|---|
| `public_url` | `"https://${public_hostname}"` when set, otherwise `null`. |

`public_url` reflects the input, not overrides in `extra_helm_values`.
Both new inputs and the output are forwarded without translation.

Cloud credential references (`db_secret_id` and
`admin_secret_id`) are mutually exclusive with the matching
`existing_secrets.db` and `existing_secrets.admin` references.

For existing deployments, an inline `db_password` or `admin_password` takes
precedence over the corresponding `db_secret_id` or `admin_secret_id`;
the cloud Secret is not read. An `existing_secrets` credential reference is
mutually exclusive with both its inline password and its cloud Secret reference.
