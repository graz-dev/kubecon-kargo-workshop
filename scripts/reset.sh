#!/usr/bin/env bash
# Back to the start of the workshop, without rebuilding the cluster or the instances:
#   - the Gitea repository is deleted and created again from the seed (all stages at INITIAL_VERSION, no pull requests)
#   - what the labs created in the Kargo project (stages, warehouses, freight, ...) is removed; the project and its credentials stay
#   - the release ceiling goes back to the first release
# Argo CD syncs the five Applications back to INITIAL_VERSION by itself.
# Guarded: without --yes (or CONFIRM=yes) it only says what it would do.
#
#   scripts/reset.sh [--yes]      SKIP_PLATFORM=1 resets only Gitea and the ceiling
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/seed.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/seed.sh"
load_env
require_tools

CONFIRM="${CONFIRM:-no}"
for arg in "$@"; do
  case "$arg" in
    --yes) CONFIRM=yes ;;
    -h | --help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument '$arg'" ;;
  esac
done
DRY_RUN=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"

printf 'Reset will:\n'
printf '  - delete and recreate %s/%s in Gitea (every stage back to %s, pull requests gone)\n' "$GITEA_ORG" "$GITEA_REPO" "$INITIAL_VERSION"
if [[ "${SKIP_PLATFORM:-0}" != 1 ]]; then
  printf '  - remove the stages, warehouses, project configs, analysis templates, promotion tasks and custom steps of the Kargo instance, all the Freight, and turn the Promotion Controller off\n'
fi
printf '  - set the release ceiling back to %s\n' "$FIRST_RELEASE"
if [[ "$CONFIRM" != yes ]]; then
  printf '\nNothing was changed. To reset: make reset CONFIRM=yes\n'
  exit 0
fi

if [[ "${SKIP_PLATFORM:-0}" != 1 ]]; then
  platform_preflight
fi
"$LIB_DIR/../gitea-up.sh" --recreate-repo
printf '%s' "$FIRST_RELEASE" >"$RELEASE_FILE"
if [[ "${SKIP_PLATFORM:-0}" != 1 ]]; then
  apply_kargo_project yes
  # The credentials of Labs 7, 11 and 12 are plain Secrets: the prune does not know them
  kargo_login
  for secret in inbox-credentials aws-creds kargo-step-snow; do
    kargo_cli delete generic-credentials --project "$KARGO_PROJECT" "$secret" >/dev/null 2>&1 || true
  done
  rm -f "$INBOX_FILE"
  # Pruning a Warehouse leaves its Freight behind, and a new Warehouse called 'app' would adopt it: delete it too
  freight=()
  while IFS= read -r name; do
    [[ -z "$name" ]] || freight+=(--name "$name")
  done < <(kargo_cli get freight --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '{print $1}')
  if ((${#freight[@]} > 0)); then
    kargo_cli delete freight --project "$KARGO_PROJECT" "${freight[@]}" >/dev/null
    ok "Freight deleted"
  fi
  # Lab 10 turns the Promotion Controller on: the next run of the labs starts with it off
  set_promotion_controller off
fi
printf '\n%sReset done.%s\n' "$_C_GREEN" "$_C_RESET"
