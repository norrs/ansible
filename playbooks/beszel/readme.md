# Beszel playbook

This playbook runs Beszel as a Docker Compose service under `/service/beszel`.

## TinyAuth access control

Beszel can be protected by TinyAuth while still allowing Beszel agents to
connect directly. Enable the integration with:

```yaml
beszel_auth_provider: tinyauth
beszel_user_creation: "false"
```

Create the matching `beszel` group in Pocket ID, add the users who should be
allowed to access Beszel, and configure the Beszel app ACL in TinyAuth:

```yaml
tinyauth_apps:
  - id: beszel
    domain: "{{ beszel_hostname }}"
    oauth_groups: beszel
```

When enabled, the playbook sets `TRUSTED_AUTH_HEADER=Remote-Email` for Beszel,
uses nginx-proxy `VIRTUAL_HOST_MULTIPORTS` to generate a separate
`/api/beszel/agent-connect` path, renders nginx-proxy snippets that copy
TinyAuth's authenticated email header to Beszel, and leaves the agent websocket
path outside TinyAuth.

The Beszel vhost also overrides `/logout` and `/sso-logout` to redirect through
TinyAuth's `/logout` page. With the custom TinyAuth image configured for
Pocket ID RP-initiated logout, this clears the TinyAuth session and then ends
the Pocket ID OIDC session before returning to Beszel.

Set `beszel_auth_provider: oauth2-proxy` to render the older oauth2-proxy
nginx snippets instead. `beszel_tinyauth_enabled` and
`beszel_oauth2_proxy_enabled` are still accepted as compatibility inputs when
`beszel_auth_provider` is unset.

Beszel's native OIDC provider is configured directly against Pocket ID when a
Pocket ID OIDC client has been stored in the 1Password item `beszel`:

```text
POCKET_ID_CLIENT_ID
POCKET_ID_CLIENT_SECRET
```

Sources:

- https://github.com/henrygd/beszel/discussions/1561
- https://beszel.dev/guide/environment-variables#trusted-auth-header
