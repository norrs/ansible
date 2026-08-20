# Beszel playbook

This playbook runs Beszel as a Docker Compose service under `/service/beszel`.

## TinyAuth access control

Beszel can be protected by TinyAuth while still allowing Beszel agents to
connect directly. Enable the integration with:

```yaml
beszel_tinyauth_enabled: true
beszel_tinyauth_internal_url: "http://tinyauth:3000"
beszel_user_creation: "false"
```

Then register Beszel as a TinyAuth app, usually in private host vars:

```yaml
tinyauth_apps:
  - id: beszel
    domain: beszel.example.com
    oauth_whitelist: "/.*/"
    oauth_groups:
      - beszel
```

Create the matching `beszel` group in Pocket ID and add the users who should be
allowed to access Beszel. With the repository's deny-by-default TinyAuth ACL
policy, `oauth_whitelist: "/.*/"` lets authenticated OAuth users reach the
group check; `oauth_groups` is the app-specific gate.

When enabled, the playbook sets `TRUSTED_AUTH_HEADER=Remote-Email` for Beszel,
uses nginx-proxy `VIRTUAL_HOST_MULTIPORTS` to generate a separate
`/api/beszel/agent-connect` path, renders nginx-proxy snippets that copy
TinyAuth's `Remote-Email` header to Beszel, and leaves the agent websocket path
outside TinyAuth.

Sources:

- https://github.com/henrygd/beszel/discussions/1561
- https://beszel.dev/guide/environment-variables#trusted-auth-header
- https://tinyauth.app/docs/guides/nginx-proxy-manager/
- https://tinyauth.app/docs/reference/headers/
- https://tinyauth.app/docs/guides/access-controls/
