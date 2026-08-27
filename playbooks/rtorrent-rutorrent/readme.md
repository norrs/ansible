# rTorrent/ruTorrent playbook

This playbook runs `crazymax/rtorrent-rutorrent` and
`crazymax/geoip-updater` as a Docker Compose service under
`/service/rtorrent-rutorrent`.

Concrete host paths, ports, UID/GID values, and media mounts belong in private
vars.

## ruTorrent web UI

Set `rtorrent_rutorrent_auth_provider: tinyauth` and
`rtorrent_rutorrent_web_hostname` to publish the ruTorrent web interface through
`nginx-proxy` and protect it with TinyAuth. Add extra browser names with
`rtorrent_rutorrent_web_aliases`. In that mode,
set `rtorrent_rutorrent_publish_rutorrent_port: false` so the browser UI is only
reachable through the TinyAuth-protected virtual hosts.

The playbook renders nginx-proxy vhost snippets that call TinyAuth's
`/api/auth/nginx` endpoint. Group access is supplied through TinyAuth app ACLs,
usually in private host vars:

```yaml
rtorrent_rutorrent_auth_provider: tinyauth
tinyauth_apps:
  - id: rtorrent
    domain: "{{ rtorrent_rutorrent_web_hostname }}"
    oauth_groups: rt,RT
```

Set `rtorrent_rutorrent_auth_provider: oauth2-proxy` to render the older
oauth2-proxy nginx snippets instead. `rtorrent_rutorrent_tinyauth_enabled` and
`rtorrent_rutorrent_oauth2_proxy_enabled` are still accepted as compatibility
inputs when `rtorrent_rutorrent_auth_provider` is unset.

## 1Password

When GeoIP updates are enabled, the MaxMind license key is read from:

```text
vault: infra.norrs
item: rtorrent-rutorrent/geoip-updater
field: license_key
```

The auth passwd files are created if missing and left untouched afterward:

```text
/service/rtorrent-rutorrent/passwd/rpc.htpasswd
/service/rtorrent-rutorrent/passwd/rutorrent.htpasswd
/service/rtorrent-rutorrent/passwd/webdav.htpasswd
```

Sources:

- https://github.com/crazy-max/docker-rtorrent-rutorrent
- https://crazymax.dev/geoip-updater/install/docker/
