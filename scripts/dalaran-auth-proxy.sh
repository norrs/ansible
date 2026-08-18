#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--fix] --host <tinyauth-host> [ssh-host]\n' "$0" >&2
}

fix=0
target_host=
ssh_host=dalaran

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fix)
      fix=1
      shift
      ;;
    --host)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      target_host=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      ssh_host=$1
      shift
      ;;
  esac
done

if [ -z "$target_host" ]; then
  usage
  exit 2
fi

printf 'Connecting to %s and checking %s\n' "$ssh_host" "$target_host"

ssh -t "$ssh_host" "sudo env TARGET_HOST=$(printf '%q' "$target_host") FIX=$(printf '%q' "$fix") bash -s" <<'REMOTE'
set -u

target_host=${TARGET_HOST:?TARGET_HOST is required}
fix=${FIX:-0}

section() {
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '+ %s\n' "$*"
  "$@" 2>&1 || true
}

shrun() {
  printf '+ %s\n' "$*"
  sh -c "$*" 2>&1 || true
}

section "Systemd"
run systemctl --no-pager -l status nginx-proxy acme-companion tinyauth

section "Docker Containers"
shrun 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}\t{{.Ports}}"'

section "TinyAuth Container Metadata"
shrun 'docker inspect tinyauth --format "state={{.State.Status}} exit={{.State.ExitCode}} networks={{json .NetworkSettings.Networks}}"'
shrun 'docker inspect tinyauth --format "{{range .Config.Env}}{{println .}}{{end}}" | grep -E "^(VIRTUAL_HOST|VIRTUAL_PORT|LETSENCRYPT_HOST|ACME_HOST)="'

section "TinyAuth Files"
run sed -n '1,80p' /service/tinyauth/compose.yaml
shrun 'grep -E "^(TINYAUTH_APPURL|TINYAUTH_OAUTH_AUTOREDIRECT|TINYAUTH_OAUTH_PROVIDERS_POCKETID_(AUTHURL|TOKENURL|USERINFOURL|REDIRECTURL|SCOPES|NAME)|TINYAUTH_OIDC_CLIENTS_BESZEL_(TRUSTEDREDIRECTURIS|NAME))=" /service/tinyauth/.env'

section "nginx-proxy Generated Config"
shrun 'docker exec nginx-proxy nginx -T 2>/dev/null | grep -n "'"$target_host"'\|ssl_reject_handshake\|default_server" | head -120'

section "nginx-proxy Mounted Files"
shrun 'docker exec nginx-proxy sh -c "ls -la /etc/nginx/conf.d /etc/nginx/certs /etc/nginx/vhost.d 2>/dev/null"'
shrun 'docker exec nginx-proxy sh -c "find /etc/nginx/certs -maxdepth 1 -type f -name \"*'"$target_host"'*\" -o -name \"'"$target_host"'*\" 2>/dev/null"'

section "Logs"
shrun 'docker logs --tail=120 nginx-proxy 2>&1'
shrun 'docker logs --tail=120 nginx-proxy-acme 2>&1'
shrun 'docker logs --tail=120 tinyauth 2>&1'

if [ "$fix" = "1" ]; then
  section "Fix: Restart Services"
  run systemctl restart tinyauth
  run systemctl restart nginx-proxy
  run systemctl restart acme-companion
  run sleep 8

  section "Post-Fix Docker Containers"
  shrun 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}\t{{.Ports}}"'

  section "Post-Fix nginx-proxy Generated Config"
  shrun 'docker exec nginx-proxy nginx -T 2>/dev/null | grep -n "'"$target_host"'\|ssl_reject_handshake\|default_server" | head -120'

  section "Post-Fix Local TLS Probe"
  shrun 'openssl s_client -connect 127.0.0.1:443 -servername "'"$target_host"'" -brief </dev/null'
fi

section "Summary Hints"
cat <<EOF
If nginx -T does not contain ${target_host}, nginx-proxy is not seeing the
TinyAuth container with VIRTUAL_HOST=${target_host}. Check the TinyAuth container
state, env, and webservers network output above.

If nginx -T contains ${target_host} but the TLS probe still fails, check the
certificate files and nginx-proxy-acme logs above.
EOF
REMOTE
