# Dalaran services

This playbook bootstraps Dalaran-local services under `/service`.

## Service layout

The Dalaran playbook composes a small self-hosted service stack:

- Docker provides the container runtime.
- `nginxproxy/nginx-proxy` and `nginxproxy/acme-companion` publish HTTPS
  virtual hosts and issue certificates with DNS-01 challenges.
- Pocket ID is the upstream identity provider and passkey login surface.
- oauth2-proxy sits at the auth boundary, authenticates users through Pocket ID,
  and provides nginx `auth_request` checks for apps without native OIDC.
- Beszel can use Pocket ID as its native OIDC provider.
- Beszel can also sit behind oauth2-proxy for per-app group ACLs. In that mode
  Beszel trusts the `Remote-Email` header and the agent websocket route is
  bypassed.
- Beszel Agent runs locally on Dalaran, self-registers with the Beszel hub, and
  collects host, Docker, and SMART disk metrics.

The intended authentication path is:

```text
Pocket ID -> oauth2-proxy -> protected apps
Pocket ID -> Beszel native OIDC
```

For different ACLs per app, create separate Pocket ID groups such as `beszel`
and `rt`, then map them in the app-specific oauth2-proxy variables:

```yaml
beszel_oauth2_proxy_allowed_groups: beszel
rtorrent_rutorrent_oauth2_proxy_allowed_groups: rt,RT
```

Broad access to oauth2-proxy can be limited in the Pocket ID OIDC client
configuration. Per-app access belongs in the app playbook vars, which are passed
to oauth2-proxy's `/oauth2/auth` endpoint as `allowed_groups`.

The oauth2-proxy playbook serves `https://auth.example.com/sso-logout`, which
clears the oauth2-proxy session and then sends the browser to Pocket ID's OIDC
end-session endpoint with the current session's `id_token_hint`.

## Playbook structure

The top-level playbook imports the service playbooks in dependency order:

```text
playbooks/docker/playbook.yaml
playbooks/nginx-proxy-with-letsencrypt/playbook.yaml
playbooks/pocket-id/playbook.yaml
playbooks/oauth2-proxy/playbook.yaml
playbooks/tinyauth-remove/playbook.yaml
playbooks/rtorrent-rutorrent/playbook.yaml
playbooks/beszel/playbook.yaml
playbooks/beszel-agent/playbook.yaml
```

oauth2-proxy skips until its Pocket ID OIDC client credentials have been stored
in 1Password. Beszel starts independently, then configures its PocketBase OIDC
provider once Beszel's Pocket ID client credentials exist. The
Beszel agent skips until at least one non-readonly Beszel user exists, because
self-registered systems must be assigned to a user.

The TinyAuth removal playbook is imported with a `never` tag. It only runs when
explicitly requested:

```bash
ansible-playbook playbooks/dalaran/playbook.yaml --tags dalaran-remove-tinyauth --ask-become-pass
```

That cleanup stops and disables the old TinyAuth service, removes its systemd
unit and old nginx-proxy vhost snippet, and leaves `/service/tinyauth` in place
unless `tinyauth_remove_purge_data: true` is set.

During the normal full Dalaran run, nginx-proxy is tested and reloaded after the
oauth2-proxy, ruTorrent, and Beszel snippets have all been rendered. To run only
that final validation step, use `--tags dalaran-nginx-validate`.

## Docker apt suite

Dalaran currently reports Debian testing/forky. Docker does not publish a
`forky` apt repository, so the Dalaran playbook sets:

```yaml
docker_apt_suite: trixie
```

This follows Docker's guidance for Debian testing/derivative systems: use the
codename of the corresponding supported Debian release.

## Private configuration

Service hostnames and DNS-01 details are intentionally kept out of the public
playbooks. The public repo expects a private group-vars file:

```text
private/group_vars/dalaran.yaml
```

Expected keys:

```yaml
pocket_id_hostname: ...
oauth2_proxy_hostname: ...
oauth2_proxy_cookie_domain: ...
beszel_hostname: ...
nginx_proxy_nsupdate_server: ...
nginx_proxy_nsupdate_zone: ...
pocket_id_trust_proxy: ...
oauth2_proxy_trusted_proxies: ...
```

The public `group_vars/dalaran.yaml` path is a symlink to that private file.

## DNS-01

Dalaran uses `nginxproxy/acme-companion` with `ACME_CHALLENGE=DNS-01` and
`acme.sh`'s `dns_nsupdate` backend. The TSIG secret is read from 1Password:

```text
vault: infra.norrs
item: bind9/named.conf.acme-dalaran
field: TSIG_SECRET
```

The same secret is rendered in two places:

```text
/etc/bind/named.conf.acme-dalaran
/service/nginx-proxy/nsupdate.key
```

The BIND include must be readable by the running BIND process, so Ansible
installs it as `root:bind 0640`.

The per-name `update-policy` grants are private:

```text
private/playbooks/bind/files/etc/bind/named.conf.acme-dalaran-policy
```

The public BIND config only includes this policy fragment from inside the
`zone` block.

## First run order

1. Create the BIND ACME TSIG secret in 1Password.
2. Run `ansible-playbook playbooks/bind/playbook.yaml --ask-become-pass`.
3. Create the Pocket ID encryption key in 1Password.
4. Run `ansible-playbook playbooks/dalaran/playbook.yaml --ask-become-pass`.
   This installs Pocket ID and Beszel. oauth2-proxy is skipped until its Pocket
   ID OIDC client credentials exist in 1Password.
5. Bootstrap Pocket ID and create the initial admin/passkey.
6. In Pocket ID, create the oauth2-proxy OIDC client:
   - Name: `oauth2-proxy`
   - Callback URL: `https://auth.example.com/oauth2/callback`
   - Logout Callback URL: `https://auth.example.com/oauth2/sign_in`
   - Allowed user groups: include the Pocket ID group containing the users who
     may use the shared auth proxy.
7. Store that Pocket ID client in 1Password item `oauth2-proxy`:
   - `POCKET_ID_CLIENT_ID`
   - `POCKET_ID_CLIENT_SECRET`
   - `COOKIE_SECRET` is generated by the playbook when missing.
8. In Pocket ID, optionally create a Beszel OIDC client for Beszel's native OIDC
   login:
   - Name: `Beszel`
   - Callback URL: `https://beszel.example.com/api/oauth2-redirect`
9. Store the Beszel Pocket ID client in 1Password item `beszel`:
   - `POCKET_ID_CLIENT_ID`
   - `POCKET_ID_CLIENT_SECRET`
10. Rerun the Dalaran playbook. The oauth2-proxy playbook starts the shared auth
   proxy, and the Beszel playbook configures Beszel's PocketBase `users`
   collection with an OpenID Connect provider when the Beszel client credentials
   exist:
   - Client ID: `POCKET_ID_CLIENT_ID` from 1Password item `beszel`
   - Client Secret: `POCKET_ID_CLIENT_SECRET` from 1Password item `beszel`
   - Display Name: `Pocket ID`
   - Auth URL: `https://pocket.example.com/authorize`
   - Token URL: `https://pocket.example.com/api/oidc/token`
   - Fetch user info from: User info URL
   - User info URL: `https://pocket.example.com/api/oidc/userinfo`
   - Support PKCE: enabled
11. Configure the local Beszel agent so Docker containers appear:
   - Log in to Beszel once so the `users` collection has an owner for systems.
   - Rerun `ansible-playbook playbooks/dalaran/playbook.yaml --ask-become-pass`.
   - The `beszel-agent` playbook derives the hub public key from
     `/service/beszel/beszel_data/id_ed25519`, creates a permanent universal
     token in the hub database when missing, and starts a local `beszel-agent`
     service with `SYSTEM_NAME=dalaran`.
   - The agent self-registers with the hub and mounts `/var/run/docker.sock:ro`,
     which is what lets Beszel collect Docker container stats.
   - SMART disk monitoring is enabled in the agent playbook. It uses
     `henrygd/beszel-agent:alpine`, detects base disk devices such as
     `/dev/sda`, `/dev/nvme0`, and `/dev/nvme1`, passes those devices into the
     container, and adds `SYS_RAWIO` / `SYS_ADMIN` as required by Beszel's Docker
     SMART guide.

## Pocket ID upgrades

Pocket ID is pinned to a concrete image tag in the Ansible playbook. When DIUN
reports a newer semver tag, update `pocket_id_default_image` in
`playbooks/pocket-id/vars.yaml`, then run the controlled upgrade tag:

```bash
scripts/play-host.bash dalaran pocket-id-upgrade --ask-become-pass
```

The upgrade task renders `/service/pocket-id/compose.yaml`, pulls the configured
image, restarts `pocket-id` only when the compose file or pulled image changed,
and waits for the public Pocket ID configuration endpoint to return HTTP 200.
