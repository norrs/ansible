# Replace only nginx and its two installed modules in the deployed application.
ARG APP_IMAGE=crazymax/rtorrent-rutorrent@sha256:8e9944b7d58b5a605905c76c290c9282ce5132b79eff8f79cec4d6b239701303
FROM ${APP_IMAGE} AS builder
USER root
RUN mkdir -p /original/etc /original/var/lib \
    && cp -a /etc/nginx /original/etc/ \
    && cp -a /var/lib/nginx /original/var/lib/ \
    && apk add --no-cache alpine-sdk linux-headers openssl-dev pcre2-dev zlib-dev libmaxminddb-dev libxml2-dev libxslt-dev
COPY APKBUILD /build/nginx/APKBUILD
WORKDIR /build/nginx
RUN apk update \
    && abuild-keygen -a -n \
    && cp /root/.abuild/*.rsa.pub /etc/apk/keys/ \
    && JOBS=4 REPODEST=/packages abuild -F -r \
    && mkdir /out \
    && cp /packages/build/*/*.apk /out/ \
    && cp /root/.abuild/*.rsa.pub /out/

FROM ${APP_IMAGE}
USER root
COPY --from=builder /out/ /tmp/nginx-security-packages/
RUN cp /tmp/nginx-security-packages/*.rsa.pub /etc/apk/keys/ \
    && apk add --no-cache /tmp/nginx-security-packages/*.apk \
    && rm -rf /tmp/nginx-security-packages \
    && nginx -v
LABEL local.nginx.security-version="1.31.9" \
      local.nginx.security-cves="CVE-2026-123007,CVE-2026-123633"
