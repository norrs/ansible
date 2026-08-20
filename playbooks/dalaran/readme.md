# Dalaran services

This playbook bootstraps Dalaran-local services under `/service`.

## Service layout

The Dalaran playbook composes a small self-hosted service stack:

- Docker provides the container runtime.
- `nginxproxy/nginx-proxy` and `nginxproxy/acme-companion` publish HTTPS
  virtual hosts and issue certificates with DNS-01 challenges.
- Pocket ID is the upstream identity provider and passkey login surface.
- TinyAuth sits at the auth boundary, authenticates users through Pocket ID,
  and also exposes an OIDC provider for downstream apps.
- Beszel uses TinyAuth as its OIDC login provider.
- Beszel can also sit behind TinyAuth's nginx auth endpoint for per-app group
  ACLs. In that mode Beszel trusts TinyAuth's `Remote-Email` header and the
  agent websocket route is bypassed.
- Beszel Agent runs locally on Dalaran, self-registers with the Beszel hub, and
  collects host, Docker, and SMART disk metrics.

The intended authentication path is:

```text
Pocket ID -> TinyAuth OAuth login -> TinyAuth OIDC provider -> Beszel
```

For different ACLs per app, create separate Pocket ID groups such as `beszel`
and `rt`, then map them in `tinyauth_apps`:

```yaml
tinyauth_apps:
  - id: beszel
    domain: beszel.example.com
    oauth_whitelist: "/.*/"
    oauth_groups:
      - beszel
  - id: rt_dalaran
    domain: rt-dalaran.example.com
    oauth_whitelist: "/.*/"
    oauth_groups:
      - rt
  - id: rt
    domain: rt.example.com
    oauth_whitelist: "/.*/"
    oauth_groups:
      - rt
```

Broad access to TinyAuth can be limited in the Pocket ID OIDC client
configuration. Per-app access belongs in `tinyauth_apps`. Because this playbook
uses `TINYAUTH_AUTH_ACLS_POLICY=deny`, OAuth-protected apps need an
`oauth_whitelist` allow rule as well as any stricter `oauth_groups` rule.
`oauth_whitelist: "/.*/"` allows authenticated OAuth identities to continue to
the group check.

The `tinyauth_apps` entries render these TinyAuth ACL keys when present:
`oauth_whitelist`, `oauth_groups`, `users_allow`, `users_block`, `ip_allow`,
`ip_block`, `ip_bypass`, `path_allow`, `path_block`, and `ldap_groups`. Values
may be strings or YAML lists; lists are rendered as comma-separated TinyAuth
environment values.

TinyAuth logout only clears TinyAuth's local session. The TinyAuth playbook also
serves `https://auth.example.com/sso-logout`, which first posts to TinyAuth's
logout endpoint and then sends the browser to Pocket ID's OIDC end-session
endpoint. Pocket ID shows a confirmation page because TinyAuth does not preserve
the upstream `id_token_hint` needed for a fully silent RP-initiated logout.

## Playbook structure

The top-level playbook imports the service playbooks in dependency order:

```text
playbooks/docker/playbook.yaml
playbooks/nginx-proxy-with-letsencrypt/playbook.yaml
playbooks/pocket-id/playbook.yaml
playbooks/tinyauth/playbook.yaml
playbooks/beszel/playbook.yaml
playbooks/beszel-agent/playbook.yaml
```

TinyAuth skips until the Pocket ID OIDC client credentials have been stored in
1Password. Beszel starts independently, then configures its PocketBase OIDC
provider once the generated TinyAuth/Beszel client credentials exist. The
Beszel agent skips until at least one non-readonly Beszel user exists, because
self-registered systems must be assigned to a user.

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
tinyauth_hostname: ...
beszel_hostname: ...
nginx_proxy_nsupdate_server: ...
nginx_proxy_nsupdate_zone: ...
pocket_id_trust_proxy: ...
tinyauth_trusted_proxies: ...
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
   This installs Pocket ID and Beszel. TinyAuth is skipped until its Pocket ID
   OIDC client credentials exist in 1Password.
5. Bootstrap Pocket ID and create the initial admin/passkey.
6. In Pocket ID, create the TinyAuth OIDC client:
   - Name: `Tinyauth`
   - Callback URL: `https://auth.example.com/api/oauth/callback/pocketid`
   - Allowed user groups: include the Pocket ID group containing the users who
     may access TinyAuth, for example `tinyauth_group`
7. Store that Pocket ID client in 1Password item `tinyauth`:
   - `POCKET_ID_CLIENT_ID`
   - `POCKET_ID_CLIENT_SECRET`
   - Leave `OAUTH_WHITELIST` empty unless you want an additional TinyAuth-side
     email/domain/regex restriction. Do not set it to a Pocket ID group name.
     When empty, this playbook renders `TINYAUTH_OAUTH_WHITELIST=/.*/` so
     TinyAuth's deny-by-default ACL policy does not block OAuth login itself;
     Pocket ID Allowed User Groups remains the access gate.
8. Rerun the Dalaran playbook. The TinyAuth playbook creates the Beszel OIDC
   client credentials in 1Password if they are missing, and the Beszel playbook
   configures Beszel's PocketBase `users` collection with an OpenID Connect
   provider:
   - Client ID: `BESZEL_CLIENT_ID` from 1Password item `tinyauth`
   - Client Secret: `BESZEL_CLIENT_SECRET` from 1Password item `tinyauth`
   - Display Name: `Tinyauth`
   - Auth URL: `https://auth.example.com/authorize`
   - Token URL: `https://auth.example.com/api/oidc/token`
   - Fetch user info from: User info URL
   - User info URL: `https://auth.example.com/api/oidc/userinfo`
   - Support PKCE: enabled
9. Configure the local Beszel agent so Docker containers appear:
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
