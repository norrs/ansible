# Container image builds

These proxy recipes reproduce the patched images currently used by the
inventory. The proxy playbook consumes the declared image and reconciles
the service configuration. ruTorrent's normal playbook also supports building
its custom image when missing, using its recipe under
`playbooks/rtorrent-rutorrent/files/image/`. Neither needs a CVE-specific rollout.

On 18 November 2026, published nginx-proxy and ruTorrent images did not yet
contain nginx's HTTP/2 fixes. The custom images retain the deployed application
versions and replace nginx with 1.31.9, which fixes CVE-2026-123007 and
CVE-2026-123633. See [nginx's advisory](https://nginx.org/en/security_advisories.html).

Build on the target Docker daemon, or build elsewhere and deliver the resulting
image with `docker save`/`docker load`. ruTorrent can build on the target host
through its normal playbook with `rtorrent_rutorrent_build_image: true`.
A registry image pinned by digest is also supported: change the relevant
inventory image reference and run its normal playbook. The current local
proxy images must be delivered before deployment; they are not published
to a registry. ruTorrent's local image is built automatically when needed.

From the repository root, the current builds are:

```bash
# Proxy application used by Dalaran (the Dockerfile defaults).
docker build -t localhost/nginx-proxy:1.31.9-bdb00dfb079a images/nginx-proxy

# Proxy application used by Diablo.
docker build \
  --build-arg PROXY_IMAGE=nginxproxy/nginx-proxy@sha256:452f458e74bee0da7083faab6896034ae6b8be9167627956e314d055ad329edd \
  --build-arg PROXY_VERSION=1.7.1-45-g4f70a63 \
  --build-arg DOCKER_GEN_VERSION=0.14.7 \
  -t localhost/nginx-proxy:1.31.9-452f458e74be images/nginx-proxy

# Optional manual build of the custom ruTorrent image.
docker build -t localhost/rtorrent-rutorrent:nginx-1.31.9-8e9944b7d58b playbooks/rtorrent-rutorrent/files/image
```

The proxy recipe preserves its source application's template, docker-gen,
forego and settings, using the official nginx image pinned by digest.
The ruTorrent recipe builds nginx and its installed DAV-ext/GeoIP2 modules
as locally signed Alpine packages. Source archives and the Alpine DAV
compatibility patches are checksum-pinned in `APKBUILD`. The nginx source
signature was verified with the nginx maintainer's published key,
fingerprint `D6786CE303D9A9022998DC6CC8464D549AF75C0A`.

The seven running nginx containers were verified at 1.31.9 after deployment.
ruTorrent kept its 0.16.5 engine and all 98 loaded torrents. UI/PHP, WebDAV,
authentication, password-file permissions and repeat-run checks passed.
