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

printf '\n'
for pair in "kargo:$AKUITY_KARGO_INSTANCE" "argocd:$AKUITY_ARGOCD_INSTANCE"; do
  kind="${pair%%:*}"
  name="${pair#*:}"
  if [[ -n "$(health_of "$kind" "$name")" ]]; then
    ak "$kind" instance delete "$name"
    ok "deleted the $kind instance $name"
  fi
done
