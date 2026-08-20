# rTorrent/ruTorrent playbook

This playbook runs `crazymax/rtorrent-rutorrent` and
`crazymax/geoip-updater` as a Docker Compose service under
`/service/rtorrent-rutorrent`.

Concrete host paths, ports, UID/GID values, and media mounts belong in private
vars.

## ruTorrent web UI

Set `rtorrent_rutorrent_tinyauth_enabled: true` and
`rtorrent_rutorrent_web_hostname` to publish the ruTorrent web interface through
`nginx-proxy` and protect it with TinyAuth. Add extra browser names with
`rtorrent_rutorrent_web_aliases`; every hostname must also be registered in
`tinyauth_apps` so TinyAuth can match the forwarded `Host` header. In that mode,
set `rtorrent_rutorrent_publish_rutorrent_port: false` so the browser UI is only
reachable through the OAuth-protected virtual hosts.

The playbook renders the nginx-proxy vhost snippets that call TinyAuth's Nginx
auth endpoint. The matching TinyAuth app registration is supplied through
`tinyauth_apps`, usually in private host vars. With the repository's
deny-by-default TinyAuth ACL policy, OAuth apps should set an OAuth allow rule
and then the group gate:

```yaml
tinyauth_apps:
  - id: rt
    domain: rt.example.com
    oauth_whitelist: "/.*/"
    oauth_groups:
      - rt
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
