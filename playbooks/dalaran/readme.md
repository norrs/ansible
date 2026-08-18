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
- Beszel Agent runs locally on Dalaran, self-registers with the Beszel hub, and
  collects host, Docker, and SMART disk metrics.

The intended authentication path is:

```text
Pocket ID -> TinyAuth OAuth login -> TinyAuth OIDC provider -> Beszel
```

Group-based access belongs in the Pocket ID OIDC client configuration. TinyAuth
`OAUTH_WHITELIST` is only an additional email/domain/regex identity filter.

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
