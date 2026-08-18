#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --all [ACL_FILE]" >&2
  echo "       $0 HOSTNAME [ACL_FILE]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

DEFAULT_ACL_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/private/playbooks/bind/files/etc/bind/named.conf.acl"
HOSTNAME="$1"
ACL_FILE="${2:-${DEFAULT_ACL_FILE}}"

if [[ -z "${HOSTNAME}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${ACL_FILE}" ]]; then
  echo "ACL file not found: ${ACL_FILE}" >&2
  exit 1
fi

if ! command -v dig >/dev/null 2>&1; then
  echo "dig is required" >&2
  exit 1
fi

update_hostname() {
  local hostname="$1"
  local marker="dynamic-ip: ${hostname}"
  local resolved_ip current_ip tmp_file

  if ! grep -qF "${marker}" "${ACL_FILE}"; then
    echo "Marker not found in ${ACL_FILE}: ${marker}" >&2
    return 1
  fi

  resolved_ip="$(dig +short A "${hostname}" | awk '/^[0-9]+(\.[0-9]+){3}$/ { print; exit }')"

  if [[ -z "${resolved_ip}" ]]; then
    echo "Could not resolve an A record for ${hostname}" >&2
    return 1
  fi

  current_ip="$(awk -v marker="${marker}" '$0 ~ marker { sub(/^[[:space:]]*/, ""); sub(/\/32;.*/, ""); print; exit }' "${ACL_FILE}")"

  if [[ "${current_ip}" == "${resolved_ip}" ]]; then
    echo "${hostname} is unchanged: ${resolved_ip}"
    return 0
  fi

  tmp_file="$(mktemp)"

  awk -v marker="${marker}" -v resolved_ip="${resolved_ip}" '
    $0 ~ marker {
      sub(/^[[:space:]]*[0-9]+(\.[0-9]+){3}\/32;/, "  " resolved_ip "/32;")
    }
    { print }
  ' "${ACL_FILE}" > "${tmp_file}"

  mv "${tmp_file}" "${ACL_FILE}"
  echo "Updated ${hostname}: ${current_ip} -> ${resolved_ip}"
}

if [[ "${HOSTNAME}" == "--all" ]]; then
  mapfile -t hostnames < <(awk '
    /dynamic-ip:/ {
      sub(/^.*dynamic-ip:[[:space:]]*/, "")
      sub(/[[:space:]].*$/, "")
      if ($0 != "") {
        print
      }
    }
  ' "${ACL_FILE}" | sort -u)

  if [[ "${#hostnames[@]}" -eq 0 ]]; then
    echo "No dynamic-ip markers found in ${ACL_FILE}" >&2
    exit 1
  fi

  for hostname in "${hostnames[@]}"; do
    update_hostname "${hostname}"
  done
else
  update_hostname "${HOSTNAME}"
fi
