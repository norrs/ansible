# oauth2-proxy playbook

This playbook runs oauth2-proxy as the shared auth middleware for services
published by `nginxproxy/nginx-proxy`.

Create an OIDC client in Pocket ID:

```text
Name: oauth2-proxy
Callback URL: https://auth.example.com/oauth2/callback
Logout Callback URL: https://auth.example.com/oauth2/sign_in
Allowed user groups: include the broad group allowed to use the proxy
```

Store the credentials in 1Password item `oauth2-proxy`:

```text
POCKET_ID_CLIENT_ID
POCKET_ID_CLIENT_SECRET
```

The playbook generates and stores `COOKIE_SECRET` in the same item when it is
missing.

Protected apps add nginx-proxy snippets under `/service/nginx-proxy/vhost.d`.
The snippets call `http://oauth2-proxy:4180/oauth2/auth` through nginx
`auth_request`, and redirect unauthenticated browser requests to
`https://auth.example.com/oauth2/start`.

Per-app access belongs in the app playbook vars, for example:

```yaml
beszel_oauth2_proxy_allowed_groups: beszel
rtorrent_rutorrent_oauth2_proxy_allowed_groups: rt,RT
```

The central `https://auth.example.com/sso-logout` endpoint signs out of
oauth2-proxy and then redirects to Pocket ID's end-session endpoint with
`id_token_hint={id_token}`.
