#!/usr/bin/with-contenv sh
# shellcheck shell=sh
set -eu

# 03-config.sh sets these files to 0644. Run after it, before nginx starts.
# Validate the entire fixed list before changing anything; never follow links.
for passwd_file in /passwd/rpc.htpasswd /passwd/rutorrent.htpasswd /passwd/webdav.htpasswd; do
  if [ ! -f "$passwd_file" ] || [ -L "$passwd_file" ]; then
    printf 'Refusing unexpected password file: %s\n' "$passwd_file" >&2
    exit 1
  fi
done

# Upstream assigns PUID:PGID ownership and runs nginx as that identity.
# Leave contents, ownership, modification times and other /passwd entries alone.
chmod 0640 /passwd/rpc.htpasswd /passwd/rutorrent.htpasswd /passwd/webdav.htpasswd
