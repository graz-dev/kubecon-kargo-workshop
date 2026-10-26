#!/usr/bin/env bash
# One-shot preparation, meant to be run by attendees a few days before the workshop:
#   1. downloads every pinned CLI into ./.tools/bin (one at a time, so one failure does not stop the rest)
#   2. runs the doctor checks
#   3. writes a plain-text report (.tools/bootstrap-report.txt) to send to the organizers if something is wrong.
# The report holds no passwords or tokens; your home directory and user name are masked.
#
#   scripts/bootstrap.sh
#
# Safe to run again at any time. Exit code 1 when a tool failed to install or a doctor check failed.
set -uo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

REPORT_VERSION=1
REPORT="$TOOLS_DIR/bootstrap-report.txt"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$TOOLS_DIR"
START="$(date +%s)"

os_pretty() {
  local name=""
  if have sw_vers; then
    printf '%s %s' "$(sw_vers -productName)" "$(sw_vers -productVersion)"
    return 0
  fi
  if [[ -r /etc/os-release ]]; then
    name="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release | head -1)"
  fi
  printf '%s' "${name:-$(uname -sr)}"
  if grep -qi microsoft /proc/version 2>/dev/null; then
    printf ' (WSL)'
  fi
}

docker_summary() {
  if ! have docker; then
    printf 'docker CLI not found'
    return 0
  fi
  printf 'client %s' "$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo '?')"
  if docker info >/dev/null 2>&1; then
    printf ', server %s, %s, context %s' \
      "$(docker info --format '{{.ServerVersion}}' 2>/dev/null)" \
      "$(docker info --format '{{.OperatingSystem}}' 2>/dev/null)" \
      "$(docker context show 2>/dev/null || echo '?')"
  else
    printf ', daemon not reachable'
  fi
}

proxy_names() {
  local var out=""
  for var in HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy; do
    if [[ -n "${!var:-}" ]]; then
      out="$out $var"
    fi
  done
  printf '%s' "${out:-none}"
}

printf '== Kargo workshop: preparing this machine ==\n\n'

# --- 1. Tools ----------------------------------------------------------------------
printf '1/2  Downloading the tools\n'
TOOLS_FAILED=""
: >"$WORK/tools.log"
for tool in $("$LIB_DIR/../tools.sh" list | awk 'NR>1{print $1}'); do
  # pipefail makes the pipeline fail when tools.sh fails, not only when tee does
  if ! "$LIB_DIR/../tools.sh" install "$tool" 2>&1 | tee -a "$WORK/tools.log"; then
    TOOLS_FAILED="$TOOLS_FAILED $tool"
  fi
done

# --- 2. Doctor ---------------------------------------------------------------------
printf '\n2/2  Checking this machine\n'
DOCTOR_REPORT_FILE="$WORK/doctor.txt" "$LIB_DIR/../doctor.sh"
DOCTOR_RC=$?

# --- Report ------------------------------------------------------------------------
{
  printf 'Kargo workshop bootstrap report (format %s)\n' "$REPORT_VERSION"
  printf 'generated:  %s UTC\n' "$(date -u +'%Y-%m-%d %H:%M:%S')"
  printf 'duration:   %ss\n' "$(($(date +%s) - START))"
  printf 'prefix:     %s\n' "${WORKSHOP_PREFIX:-<not set>}"
  printf 'repo:       %s\n' "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'no commit')"
  printf 'os:         %s, %s, kernel %s\n' "$(os_pretty)" "$(detect_arch)" "$(uname -r)"
  printf 'shell:      bash %s (login shell %s)\n' "$BASH_VERSION" "${SHELL:-?}"
  printf 'docker:     %s\n' "$(docker_summary)"
  printf 'proxy vars: %s\n' "$(proxy_names)"
  printf 'settings:   HTTP_PORT=%s WORKSHOP_DOMAIN=%s RELEASE_MODE=%s images=%s\n' \
    "$HTTP_PORT" "$WORKSHOP_DOMAIN" "$RELEASE_MODE" "$(image_repo_source)"
  printf '\nTools\n'
  "$LIB_DIR/../tools.sh" list
  cat "$WORK/doctor.txt"
  if [[ -n "$TOOLS_FAILED" ]]; then
    printf '\nTool installation problems:%s\n--- last lines of the log ---\n' "$TOOLS_FAILED"
    tail -n 15 "$WORK/tools.log"
  fi
  printf '\nRESULT: '
  if [[ -z "$TOOLS_FAILED" && "$DOCTOR_RC" == 0 ]]; then
    printf 'READY\n'
  else
    printf 'PROBLEMS\n'
  fi
} >"$WORK/report.txt"

# Mask the home directory and the user name before the report can be shared
# (replacements go through variables: bash 3.2 keeps literal quotes in a quoted replacement)
text="$(cat "$WORK/report.txt")"
tilde='~'
user_mask='<user>'
text="${text//"$HOME"/$tilde}"
if [[ -n "${USER:-}" && ${#USER} -ge 3 ]]; then
  text="${text//"$USER"/$user_mask}"
fi
printf '%s\n' "$text" >"$REPORT"

# --- Summary -----------------------------------------------------------------------
printf '\n'
if [[ -z "$TOOLS_FAILED" && "$DOCTOR_RC" == 0 ]]; then
  printf '%sAll set.%s Nothing else to do until the workshop. Keep this folder as it is.\n' "$_C_GREEN" "$_C_RESET"
  printf 'Report saved in %s (no need to send it).\n' "${REPORT#"$ROOT_DIR"/}"
  exit 0
fi

printf '%sSome things need attention:%s\n' "$_C_RED" "$_C_RESET"
if [[ -n "$TOOLS_FAILED" ]]; then
  printf '  - tools not installed:%s\n' "$TOOLS_FAILED"
fi
grep '^\[FAIL\]' "$WORK/doctor.txt" | sed 's/^\[FAIL\] */  - /' || true
printf '\nFix what you can and run this command again. If you are stuck, send us the file\n'
printf '  %s\n' "${REPORT#"$ROOT_DIR"/}"
printf 'at %s (it contains no passwords or tokens).\n' "${SUPPORT_CONTACT:-the workshop organizers}"
exit 1
