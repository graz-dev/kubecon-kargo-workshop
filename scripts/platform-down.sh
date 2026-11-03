#!/usr/bin/env bash
# Deletes what scripts/platform-up.sh created on the Akuity Platform: the Kargo instance (with its agent) and
# the Argo CD instance (with its cluster). Only the two instances named in workshop.env / .env are touched.
# Guarded: without --yes (or CONFIRM=yes) it only shows what it would delete.
#
#   scripts/platform-down.sh [--yes]
#
# Deleting an instance cannot be undone. The agents left in the kind cluster stop working; `make down` removes the cluster.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

CONFIRM="${CONFIRM:-no}"
for arg in "$@"; do
  case "$arg" in
    --yes) CONFIRM=yes ;;
    -h | --help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument '$arg'" ;;
  esac
done

[[ -x "$TOOLS_BIN/akuity" ]] || die "The akuity CLI is not installed in $TOOLS_BIN. Run: make tools"
require_prefix
akuity_logged_in || die "You are not logged in to $AKUITY_SERVER_URL. Run: make login"
ORG="$(akuity_org)"
ak() { akuity "$@" --server "$AKUITY_SERVER_URL" --organization-name "$ORG"; }
health_of() { ak "$1" instance list 2>/dev/null | awk -v n="$2" 'NR>1 && $2==n {print $3}'; }

printf 'Organization %s on %s\n' "$ORG" "$AKUITY_SERVER_URL"
FOUND=0
for pair in "kargo:$AKUITY_KARGO_INSTANCE" "argocd:$AKUITY_ARGOCD_INSTANCE"; do
  kind="${pair%%:*}"
  name="${pair#*:}"
  h="$(health_of "$kind" "$name")"
  if [[ -n "$h" ]]; then
    printf '  will delete the %s instance %s (%s)\n' "$kind" "$name" "$h"
    FOUND=1
  else
    printf '  no %s instance named %s: nothing to delete\n' "$kind" "$name"
  fi
done
((FOUND == 1)) || exit 0

if [[ "$CONFIRM" != yes ]]; then
  printf '\nDry run: nothing was deleted. To delete: make platform-down CONFIRM=yes\n'
  exit 0
fi

# The platform deletes an instance in the background. Argo CD cannot go while the Kargo agent linked to it still exists, so wait for
# the Kargo instance to disappear, and try the deletion again for about two minutes when the platform still sees an agent.
delete_instance() { # <kind> <name>
  local kind="$1" name="$2" out
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if out="$(ak "$kind" instance delete "$name" 2>&1)"; then
      printf '%s\n' "$out"
      ok "deleted the $kind instance $name"
      return 0
    fi
    case "$out" in
      *"connected kargo agents"* | *"connected agents"*)
        info "the platform still sees an agent of $name: trying again in 10 seconds"
        sleep 10
        ;;
      *)
        printf '%s\n' "$out" >&2
        return 1
        ;;
    esac
  done
  printf '%s\n' "$out" >&2
  return 1
}

wait_gone() { # <kind> <name>
  local kind="$1" name="$2"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
    [[ -n "$(health_of "$kind" "$name")" ]] || return 0
    sleep 10
  done
  warn "the $kind instance $name is still on the platform after three minutes"
}

printf '\n'
for pair in "kargo:$AKUITY_KARGO_INSTANCE" "argocd:$AKUITY_ARGOCD_INSTANCE"; do
  kind="${pair%%:*}"
  name="${pair#*:}"
  if [[ -n "$(health_of "$kind" "$name")" ]]; then
    delete_instance "$kind" "$name"
    wait_gone "$kind" "$name"
  fi
done
