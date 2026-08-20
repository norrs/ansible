#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT_DIR}/inventory.yaml}"
ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF="${ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF:-op://Private/ansible-homelab-service-account/password}"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [HOST] [PART] [ansible-playbook args...]

Run all or one tagged part of a host/top-level playbook.

With no HOST or PART, the script opens an interactive menu. The first menu can
select one or more host/top-level playbooks. If one playbook is selected, a
second menu selects all or one tagged part. If multiple playbooks are selected,
the selected playbooks are run in full in one ansible-playbook invocation.
If fzf is available, it is used for selection; set PLAY_HOST_SELECTOR=number to
use the plain numbered menu.
Interactive mode prompts whether to include --ask-become-pass unless extra
ansible-playbook args are already supplied.
Selectable playbooks are discovered dynamically from playbooks/*/playbook.yaml,
excluding playbooks that are imported by another top-level playbook.
PART may be "all", a short tag name such as "wireguard", or the full tag name
such as "diablo-wireguard".

Examples:
  scripts/play-host.bash
  scripts/play-host.bash diablo all --ask-become-pass
  scripts/play-host.bash diablo wireguard --ask-become-pass
  scripts/play-host.bash diablo beszel-agent --ask-become-pass
  scripts/play-host.bash diablo hosts-entry --ask-become-pass --check --diff

Set ANSIBLE_INVENTORY to override the inventory path.
Set ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF to override the 1Password secret
reference used to load OP_SERVICE_ACCOUNT_TOKEN. If OP_SERVICE_ACCOUNT_TOKEN
is already set, the existing value is used and no interactive 1Password lookup
is performed.
EOF
}

die() {
  echo "$*" >&2
  exit 2
}

load_1password_service_account() {
  local token

  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    return 0
  fi

  command -v op >/dev/null 2>&1 ||
    die "1Password CLI (op) is required to load the Ansible service-account token."

  token="$(op read "${ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF}")" ||
    die "Failed to read Ansible service-account token from ${ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF}."

  [[ -n "${token}" ]] ||
    die "1Password returned an empty Ansible service-account token."

  export OP_SERVICE_ACCOUNT_TOKEN="${token}"
  unset token
}

is_interactive() {
  [[ -t 0 && -t 1 ]]
}

playbook_for_host() {
  local host="$1"
  local playbook="${ROOT_DIR}/playbooks/${host}/playbook.yaml"

  [[ -f "${playbook}" ]] || return 1
  printf '%s\n' "${playbook}"
}

list_host_playbooks() {
  local imported_file
  local imported_dir
  local playbook
  local dir
  local name
  local imported=()

  while IFS= read -r imported_file; do
    imported_file="${imported_file#../}"
    imported_dir="${imported_file%%/*}"
    imported+=("${imported_dir}")
  done < <(
    awk '
      /import_playbook:[[:space:]]*\.\.\// {
        sub(/^.*import_playbook:[[:space:]]*/, "")
        gsub(/["'\'']/, "")
        print
      }
    ' "${ROOT_DIR}"/playbooks/*/playbook.yaml 2>/dev/null | sort -u
  )

  while IFS= read -r playbook; do
    dir="$(dirname "${playbook}")"
    name="$(basename "${dir}")"

    if printf '%s\n' "${imported[@]}" | grep -qxF "${name}"; then
      continue
    fi

    printf '%s\n' "${name}"
  done < <(find "${ROOT_DIR}/playbooks" -mindepth 2 -maxdepth 2 -name playbook.yaml | sort)
}

list_tags_for_host() {
  local host="$1"
  local playbook="$2"

  awk -v prefix="${host}-" '
    {
      while (match($0, prefix "[A-Za-z0-9_-]+")) {
        tag = substr($0, RSTART, RLENGTH)
        if (!seen[tag]++) {
          print tag
        }
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
  ' "${playbook}"
}

short_part_name() {
  local host="$1"
  local tag="$2"
  printf '%s\n' "${tag#${host}-}"
}

choose_from() {
  local prompt="$1"
  shift
  local choices=("$@")
  local choice selected

  if command -v fzf >/dev/null 2>&1 && [[ "${PLAY_HOST_SELECTOR:-fzf}" != "number" ]]; then
    selected="$(printf '%s\n' "${choices[@]}" | fzf --prompt="${prompt} " --height=40% --border)" ||
      die "No selection made."
    printf '%s\n' "${selected}"
    return 0
  fi

  echo "${prompt}" >&2
  local i
  for i in "${!choices[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "${choices[$i]}" >&2
  done

  while true; do
    read -r -p "> " choice
    if [[ "${choice}" =~ ^[0-9]+$ ]] &&
      ((choice >= 1 && choice <= ${#choices[@]})); then
      printf '%s\n' "${choices[$((choice - 1))]}"
      return 0
    fi
    echo "Choose a number from 1 to ${#choices[@]}." >&2
  done
}

choose_multiple_from() {
  local prompt="$1"
  shift
  local choices=("$@")
  local selected selection part start end i
  local -A seen=()

  if command -v fzf >/dev/null 2>&1 && [[ "${PLAY_HOST_SELECTOR:-fzf}" != "number" ]]; then
    selected="$(printf '%s\n' "${choices[@]}" |
      fzf --multi --prompt="${prompt} " --height=40% --border \
        --bind 'ctrl-a:select-all,ctrl-d:deselect-all')" ||
      die "No selection made."
    [[ -n "${selected}" ]] || die "No selection made."
    printf '%s\n' "${selected}"
    return 0
  fi

  echo "${prompt}" >&2
  local index
  for index in "${!choices[@]}"; do
    printf '  %2d) %s\n' "$((index + 1))" "${choices[$index]}" >&2
  done

  while true; do
    read -r -p "> " selection
    selection="${selection//[[:space:]]/}"

    if [[ "${selection}" == "all" ]]; then
      printf '%s\n' "${choices[@]}"
      return 0
    fi

    IFS=',' read -r -a parts <<< "${selection}"
    selected=()
    seen=()

    for part in "${parts[@]}"; do
      if [[ "${part}" =~ ^[0-9]+$ ]]; then
        start="${part}"
        end="${part}"
      elif [[ "${part}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        start="${BASH_REMATCH[1]}"
        end="${BASH_REMATCH[2]}"
        if ((start > end)); then
          i="${start}"
          start="${end}"
          end="${i}"
        fi
      else
        selected=()
        break
      fi

      if ((start < 1 || end > ${#choices[@]})); then
        selected=()
        break
      fi

      for ((i = start; i <= end; i++)); do
        if [[ -z "${seen[$i]:-}" ]]; then
          selected+=("${choices[$((i - 1))]}")
          seen[$i]=1
        fi
      done
    done

    if [[ "${#selected[@]}" -gt 0 ]]; then
      printf '%s\n' "${selected[@]}"
      return 0
    fi

    echo "Choose numbers separated by commas, ranges like 1-3, or all." >&2
  done
}

confirm_yes_no() {
  local prompt="$1"
  local answer

  read -r -p "${prompt} [Y/n] " answer
  case "${answer}" in
    ""|Y|y|yes|YES)
      return 0
      ;;
    N|n|no|NO)
      return 1
      ;;
    *)
      echo "Answer yes or no." >&2
      confirm_yes_no "${prompt}"
      ;;
  esac
}

resolve_part_tag() {
  local host="$1"
  local part="$2"
  shift 2
  local tags=("$@")
  local tag

  [[ "${part}" == "all" ]] && return 0

  for tag in "${tags[@]}"; do
    if [[ "${part}" == "${tag}" || "${part}" == "$(short_part_name "${host}" "${tag}")" ]]; then
      printf '%s\n' "${tag}"
      return 0
    fi
  done

  return 1
}

run_host_part() {
  local host="$1"
  local part="$2"
  shift 2
  local playbook tag
  local tags=()

  playbook="$(playbook_for_host "${host}")" ||
    die "No host playbook found: playbooks/${host}/playbook.yaml"

  mapfile -t tags < <(list_tags_for_host "${host}" "${playbook}")
  load_1password_service_account

  if [[ "${part}" == "all" ]]; then
    exec ansible-playbook -i "${INVENTORY}" "${playbook}" "$@"
  fi

  tag="$(resolve_part_tag "${host}" "${part}" "${tags[@]}")" ||
    die "Unknown part '${part}' for host '${host}'. Run without PART to choose from the menu."

  exec ansible-playbook -i "${INVENTORY}" "${playbook}" --tags "${tag}" "$@"
}

run_host_playbooks() {
  local host
  local playbook
  local playbooks=()

  while [[ $# -gt 0 && "${1}" != "--" ]]; do
    host="$1"
    shift

    playbook="$(playbook_for_host "${host}")" ||
      die "No host playbook found: playbooks/${host}/playbook.yaml"
    playbooks+=("${playbook}")
  done

  [[ "${1:-}" == "--" ]] || die "Internal error: missing argument separator."
  shift

  load_1password_service_accountO

  exec ansible-playbook -i "${INVENTORY}" "${playbooks[@]}" "$@"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

host=
part=
extra_args=()
interactive_mode=0
selected_hosts=()

if [[ $# -gt 0 && "${1}" != -* ]]; then
  host="$1"
  shift
fi

if [[ $# -gt 0 && "${1}" != -* ]]; then
  part="$1"
  shift
fi

extra_args=("$@")

if [[ -z "${host}" ]]; then
  is_interactive || {
    usage
    exit 2
  }
  interactive_mode=1
  mapfile -t host_playbooks < <(list_host_playbooks)
  [[ "${#host_playbooks[@]}" -gt 0 ]] || die "No host playbooks found."
  mapfile -t selected_hosts < <(choose_multiple_from "Select host/top-level playbook(s):" "${host_playbooks[@]}")
  [[ "${#selected_hosts[@]}" -gt 0 ]] || die "No selection made."

  if [[ "${#selected_hosts[@]}" -gt 1 ]]; then
    if [[ "${#extra_args[@]}" -eq 0 ]]; then
      if confirm_yes_no "Include --ask-become-pass?"; then
        extra_args+=(--ask-become-pass)
      fi
    fi
    run_host_playbooks "${selected_hosts[@]}" -- "${extra_args[@]}"
  fi

  host="${selected_hosts[0]}"
fi

playbook="$(playbook_for_host "${host}")" ||
  die "No host playbook found: playbooks/${host}/playbook.yaml"

mapfile -t tags < <(list_tags_for_host "${host}" "${playbook}")

if [[ -z "${part}" ]]; then
  if ! is_interactive; then
    run_host_part "${host}" all "${extra_args[@]}"
  fi

  interactive_mode=1
  parts=(all)
  for tag in "${tags[@]}"; do
    parts+=("$(short_part_name "${host}" "${tag}")")
  done
  part="$(choose_from "Select part for ${host}:" "${parts[@]}")"
fi

if [[ "${interactive_mode}" == "1" && "${#extra_args[@]}" -eq 0 ]]; then
  if confirm_yes_no "Include --ask-become-pass?"; then
    extra_args+=(--ask-become-pass)
  fi
fi

run_host_part "${host}" "${part}" "${extra_args[@]}"
