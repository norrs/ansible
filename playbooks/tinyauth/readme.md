# TinyAuth playbook

This playbook runs TinyAuth as the shared auth middleware for services
published by `nginxproxy/nginx-proxy`.

Create an OIDC client in Pocket ID:

```text
Name: TinyAuth
Callback URL: https://auth.example.com/api/oauth/callback/pocketid
Logout Callback URL: https://auth.example.com/api/user/logout/callback
Allowed user groups: include the broad group allowed to use TinyAuth
```

Store the credentials in the 1Password item `tinyauth`:

```text
POCKET_ID_CLIENT_ID
POCKET_ID_CLIENT_SECRET
```

The playbook configures Pocket ID as the OAuth login provider. A custom
TinyAuth image can be deployed by setting `tinyauth_image`.

Protected apps add nginx-proxy snippets under `/service/nginx-proxy/vhost.d`.
The snippets call `http://tinyauth:3000/api/auth/nginx` through nginx
`auth_request`. App access belongs in `tinyauth_apps`, for example:

```yaml
tinyauth_apps:
  - id: beszel
    domain: beszel.example.com
    oauth_groups: beszel
```

The default `tinyauth_auth_acls_policy` is `allow`. With `allow`, per-app
`oauth_groups` still restrict matching apps to users in those groups. This stack
only configures the Pocket ID OAuth provider, so app access is controlled by the
Pocket ID groups returned to TinyAuth.

TinyAuth's built-in `/logout` page clears the TinyAuth session and, when using
the custom `tinyauth_image` with RP-initiated logout support, redirects to
Pocket ID's `/api/oidc/end-session` endpoint with the stored ID token hint.
Register `https://auth.example.com/api/user/logout/callback` as the Pocket ID
logout callback URL so Pocket ID can return to TinyAuth after SSO logout.
The auth vhost also exposes `/sso-logout` as a query-preserving alias for
`/logout`.
