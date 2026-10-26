#!/usr/bin/env bash
# Creates the initial state the labs start from:
#   1. Gitea with the GitOps repository (scripts/gitea-up.sh)
#   2. on the Akuity Platform: the Argo CD AppProject and ApplicationSet (one Application per stage, all at
#      INITIAL_VERSION) and the Kargo project with the credentials Kargo pushes to Gitea with
# Idempotent. Warehouses and Stages are NOT created here: they are the labs.
#
#   scripts/seed.sh        SKIP_PLATFORM=1 does the local part only; DRY_RUN=1 shows what it would apply on the platform
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/seed.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/seed.sh"
load_env
require_tools

DRY_RUN="${DRY_RUN:-0}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
step() { printf '\n%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }

cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"
if [[ "${SKIP_PLATFORM:-0}" != 1 ]]; then
  platform_preflight
fi

"$LIB_DIR/../gitea-up.sh"
[[ -f "$RELEASE_FILE" ]] || printf '%s' "$FIRST_RELEASE" >"$RELEASE_FILE"

if [[ "${SKIP_PLATFORM:-0}" == 1 ]]; then
  printf '\nSKIP_PLATFORM=1: the Argo CD applications and the Kargo project were not applied.\n'
  exit 0
fi

[[ "$DRY_RUN" != 1 ]] || printf '\n%sDRY RUN%s: Gitea above is real; the platform is only read.\n' "$_C_YELLOW" "$_C_RESET"
step "Argo CD: AppProject and ApplicationSet on '$ARGO'"
apply_argocd_apps
step "Kargo: project '$KARGO_PROJECT' and the Gitea credentials on '$KARGO'"
apply_kargo_project no

if [[ "$DRY_RUN" != 1 ]]; then
  printf '\n%sSeeded.%s Argo CD will create the five Applications; they run version %s.\n' "$_C_GREEN" "$_C_RESET" "$INITIAL_VERSION"
  printf '  Argo CD: %s\n  Kargo:   %s\n' "$(akuity_instance_url argocd "$ARGO" "$ORG")" "$(akuity_instance_url kargo "$KARGO" "$ORG")"
fi
