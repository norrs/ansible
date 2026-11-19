# Keep the deployed proxy template, docker-gen and forego versions; replace
# their nginx runtime with the official CVE-2026-123007/123633 fixed image.
ARG PROXY_IMAGE=nginxproxy/nginx-proxy@sha256:bdb00dfb079a51097da03df5a9de935c29d6975d6d3606925b250e58ee440a2a
ARG NGINX_IMAGE=nginx:1.31.9@sha256:08f354a3b44c422021a5c0f5efb3e27f8f90236b5447d3bac4053f5f50ab6760
FROM ${PROXY_IMAGE} AS proxy
FROM ${NGINX_IMAGE}
COPY --from=proxy /usr/local/bin/forego /usr/local/bin/forego
COPY --from=proxy /usr/local/bin/docker-gen /usr/local/bin/docker-gen
COPY --from=proxy /app/ /app/
COPY --from=proxy /etc/nginx/ /etc/nginx/
RUN mkdir -p /etc/nginx/toplevel.conf.d /etc/nginx/dhparam /etc/nginx/certs /usr/share/nginx/html/errors
ARG PROXY_VERSION=1.11.6-6-g805c742
ARG DOCKER_GEN_VERSION=0.17.2
ENV NGINX_PROXY_VERSION=${PROXY_VERSION} \
    DOCKER_GEN_VERSION=${DOCKER_GEN_VERSION} \
    DOCKER_HOST=unix:///tmp/docker.sock
WORKDIR /app
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["forego", "start", "-r"]
