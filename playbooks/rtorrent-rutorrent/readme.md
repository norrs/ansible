# rTorrent/ruTorrent playbook

This playbook runs `crazymax/rtorrent-rutorrent` and
`crazymax/geoip-updater` as a Docker Compose service under
`/service/rtorrent-rutorrent`.

Concrete host paths, ports, UID/GID values, and media mounts belong in private
vars.

## ruTorrent web UI

Set `rtorrent_rutorrent_oauth2_proxy_enabled: true` and
`rtorrent_rutorrent_web_hostname` to publish the ruTorrent web interface through
`nginx-proxy` and protect it with oauth2-proxy. Add extra browser names with
`rtorrent_rutorrent_web_aliases`. In that mode,
set `rtorrent_rutorrent_publish_rutorrent_port: false` so the browser UI is only
reachable through the OAuth-protected virtual hosts.

The playbook renders nginx-proxy vhost snippets that call oauth2-proxy's
`/oauth2/auth` endpoint. Group access is supplied directly through the
ruTorrent vars, usually in private host vars:

```yaml
rtorrent_rutorrent_oauth2_proxy_enabled: true
rtorrent_rutorrent_oauth2_proxy_allowed_groups: rt,RT
```

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
