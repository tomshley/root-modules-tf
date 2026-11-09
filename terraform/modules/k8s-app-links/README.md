# k8s-app-links

Pure locals and outputs: creates zero resources and requires no providers.
Renders Apple and Android association JSON for `k8s-static-responder.files`.
Does not publish files, create routes, configure TLS or DNS, register app
entitlements, sign apps, configure redirects, or verify an installed mobile app.

## Inputs

`apps` is required and has this exact type:

```hcl
list(object({
  name = string
  ios = optional(object({
    team_id   = string
    bundle_id = string
    paths     = list(string)
  }))
  android = optional(object({
    package_name        = string
    sha256_fingerprints = list(string)
  }))
}))
```

Each app needs at least one platform. The name is informational and is not
rendered in the output; it must be non-null and non-empty with no leading or
trailing whitespace, and need not be unique. Team IDs match
`^[A-Z0-9]{10}$`; iOS bundle IDs are non-empty and unique, with a non-empty
callback-path list whose members begin with `/` and contain no `?`, `#`,
whitespace or control characters. Android package names are
non-empty and unique, with a non-empty list of SHA-256 fingerprints matching
`^([0-9A-F]{2}:){31}[0-9A-F]{2}$`. Incomplete and null inputs fail at plan time.
Bundle IDs and package names must equal their trimmed values and must not
contain whitespace or Unicode Cc control characters.
`apps = []` emits no placeholder files. Only declared platforms emit files.
iOS component patterns are passed through; the consumer owns their scope.

## Formats and platform responsibilities

Apple JSON uses `applinks.details[].appIDs` and `components`, with each
callback path emitted as a `"/"` component. App IDs are `team_id.bundle_id`.
Apple documents the identifier prefix as the Application Identifier Prefix;
consumers must ensure their supplied Team ID is the actual prefix for the app.

Official sources:
- https://developer.apple.com/documentation/bundleresources/applinks
- https://developer.apple.com/documentation/xcode/supporting-associated-domains
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)

The HTTPS callback API requires an associated domain. These documents describe
`webcredentials` for shared web credentials, not as a requirement for this
callback API. This renderer therefore does not grant credential-sharing access
through `webcredentials.apps`. Configure the associated-domain entitlement
and check callback behavior in the consumer's supported Apple OS versions.

Android JSON uses `delegate_permission/common.handle_all_urls` with
`namespace = "android_app"`, `package_name`, and `sha256_cert_fingerprints`.
The consumer supplies fingerprints for the actual installed app's signing
certificates and owns its intent filters.

Official sources:
- https://developers.google.com/digital-asset-links/v1/getting-started
- https://developer.android.com/training/app-links/configure-assetlinks

Both platforms require correct HTTPS hosting on the associated hostname. Apple
requires no redirects and a valid certificate. Rendering is not runtime proof.

## Outputs

- `files`: `/.well-known/apple-app-site-association` and/or
  `/.well-known/assetlinks.json`, each `{ content, content_type = "application/json" }`.
- `paths`: sorted keys present in `files`.
- `callback_paths`: iOS callback paths flattened in app/path input order.

Pass `module.app_links.files` to the responder and use `callback_paths` for
consumer-owned redirect-URI consistency checks. No hostname is an input.
