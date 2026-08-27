#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT_DIR}/inventory.yaml}"
ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF="${ANSIBLE_OP_SERVICE_ACCOUNT_TOKEN_REF:-op://Private/ansible-homelab-service-account/password}"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [HOST] [PART|ordered-tags] [ansible-playbook args...]

Run all or one tagged part of a host/top-level playbook.

With no HOST or PART, the script first asks for a run mode. Single-part mode
selects one host/top-level playbook and then all or one tagged part.
Ordered-tags mode selects one host/top-level playbook and then several tags to
run one at a time in the selected order. Full-playbook mode selects one or more
host/top-level playbooks and runs them in full in one ansible-playbook
invocation.
If fzf is available, it is used for selection; set PLAY_HOST_SELECTOR=number to
use the plain numbered menu.
Interactive mode prompts whether to include --ask-become-pass unless extra
ansible-playbook args are already supplied.
Selectable playbooks are discovered dynamically from playbooks/*/playbook.yaml,
excluding playbooks that are imported by another top-level playbook.
PART may be "all", a short tag name such as "wireguard", or the full tag name
such as "diablo-wireguard".
PART may also be "ordered-tags" or "tags" to choose several tags interactively
and run them one at a time in the selected order.

Examples:
  scripts/play-host.bash
  scripts/play-host.bash diablo all --ask-become-pass
  scripts/play-host.bash diablo wireguard --ask-become-pass
  scripts/play-host.bash diablo beszel-agent --ask-become-pass
  scripts/play-host.bash diablo hosts-entry --ask-become-pass --check --diff
  scripts/play-host.bash dalaran ordered-tags --ask-become-pass

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

choose_ordered_from() {
  local prompt="$1"
  shift
  local choices=("$@")
  local remaining=("${choices[@]}")
  local selected=()
  local choice picked done_choice

  done_choice="[done] run selected"

  if command -v fzf >/dev/null 2>&1 && [[ "${PLAY_HOST_SELECTOR:-fzf}" != "number" ]]; then
    while [[ "${#remaining[@]}" -gt 0 ]]; do
      picked="$(
        {
          printf '%s\n' "${done_choice}"
          printf '%s\n' "${remaining[@]}"
        } |
          fzf --prompt="${prompt} " --height=40% --border \
            --header="Selected: ${selected[*]:-(none)}"
      )" || die "No selection made."

      if [[ "${picked}" == "${done_choice}" ]]; then
        break
      fi

      selected+=("${picked}")
      local next=()
      local item
      for item in "${remaining[@]}"; do
        [[ "${item}" == "${picked}" ]] || next+=("${item}")
      done
      remaining=("${next[@]}")
    done

    [[ "${#selected[@]}" -gt 0 ]] || die "No tags selected."
    printf '%s\n' "${selected[@]}"
    return 0
  fi

  local -A selected_index=()

  while true; do
    echo "${prompt}" >&2
    echo "Selected: ${selected[*]:-(none)}" >&2
    echo "   0) ${done_choice}" >&2

    local index
    local marker
    for index in "${!choices[@]}"; do
      marker=" "
      if [[ -n "${selected_index[$index]:-}" ]]; then
        marker="x"
      fi
      printf '  %2d) [%s] %s\n' "$((index + 1))" "${marker}" "${choices[$index]}" >&2
    done

    read -r -p "> " choice
    choice="${choice//[[:space:]]/}"

    if [[ "${choice}" == "0" || "${choice}" == "done" ]]; then
      break
    fi

    if [[ "${choice}" =~ ^[0-9]+$ ]] &&
      ((choice >= 1 && choice <= ${#choices[@]})); then
      index="$((choice - 1))"
      if [[ -n "${selected_index[$index]:-}" ]]; then
        echo "${choices[$index]} is already selected." >&2
        continue
      fi
      selected+=("${choices[$index]}")
      selected_index[$index]=1
      if [[ "${#selected[@]}" -eq "${#choices[@]}" ]]; then
        break
      fi
      continue
    fi

    echo "Choose a number or 0/done." >&2
  done

  [[ "${#selected[@]}" -gt 0 ]] || die "No tags selected."
  printf '%s\n' "${selected[@]}"
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

is_ordered_tags_mode() {
  [[ "${1}" == "ordered-tags" || "${1}" == "tags" ]]
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

  load_1password_service_account

  exec ansible-playbook -i "${INVENTORY}" "${playbooks[@]}" "$@"
}

run_ordered_tags() {
  local host="$1"
  shift
  local playbook
  local tags=()
  local tag

  while [[ $# -gt 0 && "${1}" != "--" ]]; do
    tags+=("$1")
    shift
  done

  [[ "${1:-}" == "--" ]] || die "Internal error: missing argument separator."
  shift
  [[ "${#tags[@]}" -gt 0 ]] || die "No tags selected."

  playbook="$(playbook_for_host "${host}")" ||
    die "No host playbook found: playbooks/${host}/playbook.yaml"

  load_1password_service_account

  for tag in "${tags[@]}"; do
    echo "Running ${host}: ${tag}" >&2
    ansible-playbook -i "${INVENTORY}" "${playbook}" --tags "${tag}" "$@"
  done
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
run_mode=

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

  run_mode="$(choose_from "Select run mode:" "single part" "ordered tags" "full playbook(s)")"

  if [[ "${run_mode}" == "full playbook(s)" ]]; then
    mapfile -t selected_hosts < <(choose_multiple_from "Select host/top-level playbook(s):" "${host_playbooks[@]}")
    [[ "${#selected_hosts[@]}" -gt 0 ]] || die "No selection made."

    if [[ "${#extra_args[@]}" -eq 0 ]]; then
      if confirm_yes_no "Include --ask-become-pass?"; then
        extra_args+=(--ask-become-pass)
      fi
    fi
    run_host_playbooks "${selected_hosts[@]}" -- "${extra_args[@]}"
  fi

  host="$(choose_from "Select host/top-level playbook:" "${host_playbooks[@]}")"

  if [[ "${run_mode}" == "ordered tags" ]]; then
    part="ordered-tags"
  fi
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
  parts+=(ordered-tags)
  for tag in "${tags[@]}"; do
    parts+=("$(short_part_name "${host}" "${tag}")")
  done
  part="$(choose_from "Select part for ${host}:" "${parts[@]}")"
fi

if is_ordered_tags_mode "${part}"; then
  is_interactive || die "ordered-tags mode requires an interactive terminal."

  tag_parts=()
  for tag in "${tags[@]}"; do
    tag_parts+=("$(short_part_name "${host}" "${tag}")")
  done

  mapfile -t selected_parts < <(choose_ordered_from "Select tags for ${host} in run order:" "${tag_parts[@]}")
  selected_tags=()
  for selected_part in "${selected_parts[@]}"; do
    selected_tags+=("$(resolve_part_tag "${host}" "${selected_part}" "${tags[@]}")")
  done

  if [[ "${#extra_args[@]}" -eq 0 ]]; then
    if confirm_yes_no "Include --ask-become-pass?"; then
      extra_args+=(--ask-become-pass)
    fi
  fi

  run_ordered_tags "${host}" "${selected_tags[@]}" -- "${extra_args[@]}"
  exit 0
fi

if [[ "${interactive_mode}" == "1" && "${#extra_args[@]}" -eq 0 ]]; then
  if confirm_yes_no "Include --ask-become-pass?"; then
    extra_args+=(--ask-become-pass)
  fi
fi

run_host_part "${host}" "${part}" "${extra_args[@]}"
