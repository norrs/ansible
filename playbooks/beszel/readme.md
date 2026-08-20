# Beszel playbook

This playbook runs Beszel as a Docker Compose service under `/service/beszel`.

## oauth2-proxy access control

Beszel can be protected by oauth2-proxy while still allowing Beszel agents to
connect directly. Enable the integration with:

```yaml
beszel_oauth2_proxy_enabled: true
beszel_oauth2_proxy_allowed_groups: beszel
beszel_user_creation: "false"
```

Create the matching `beszel` group in Pocket ID and add the users who should be
allowed to access Beszel. The nginx-proxy auth snippet passes
`allowed_groups=beszel` to oauth2-proxy's `/oauth2/auth` endpoint.

When enabled, the playbook sets `TRUSTED_AUTH_HEADER=Remote-Email` for Beszel,
uses nginx-proxy `VIRTUAL_HOST_MULTIPORTS` to generate a separate
`/api/beszel/agent-connect` path, renders nginx-proxy snippets that copy
oauth2-proxy's authenticated email header to Beszel, and leaves the agent
websocket path outside oauth2-proxy.

Beszel's native OIDC provider is configured directly against Pocket ID when a
Pocket ID OIDC client has been stored in the 1Password item `beszel`:

```text
POCKET_ID_CLIENT_ID
POCKET_ID_CLIENT_SECRET
```

Sources:

- https://github.com/henrygd/beszel/discussions/1561
- https://beszel.dev/guide/environment-variables#trusted-auth-header
- https://oauth2-proxy.github.io/oauth2-proxy/features/endpoints/
