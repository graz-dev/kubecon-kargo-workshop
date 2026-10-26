# shellcheck shell=bash
# What `make seed` and `make reset` put on the Akuity Platform. Source this file after lib/common.sh.
# Needs: ORG, ARGO, KARGO, WORK (a temp dir) and DRY_RUN to be set by the caller.

# Argo CD: the AppProject and the ApplicationSet that make one Application per stage
apply_argocd_apps() {
  local dir="$WORK/argocd-apps" f
  mkdir -p "$dir"
  export GITEA_REPO_URL GITEA_BRANCH
  GITEA_REPO_URL="$(gitea_repo_url)"
  for f in appproject applicationset; do
    render_template "$ROOT_DIR/platform/argocd-apps/$f.yaml" >"$dir/$f.yaml"
  done
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] akuity argocd apply -f <AppProject and ApplicationSet> --name %s\n' "$ARGO"
    sed 's/^/      | /' "$dir/applicationset.yaml" | sed -n '/spec:/,$p' | head -30
  else
    akuity argocd apply -f "$dir" --name "$ARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG"
  fi
}

# Kargo: the project and the credentials Kargo pushes to Gitea with. With prune=yes everything else in the
# project that the labs created (stages, warehouses, ...) is removed.
apply_kargo_project() {
  local prune="${1:-no}" dir="$WORK/kargo-project" token
  mkdir -p "$dir"
  token="$(sed -n 's/^GITEA_BOT_TOKEN=//p' "$GITEA_ENV")"
  [[ -n "$token" ]] || die "No token for kargo-bot in $GITEA_ENV. Run: make seed"
  export B64_REPO_URL B64_USERNAME B64_PASSWORD
  B64_REPO_URL="$(printf '%s' "$(gitea_repo_url)" | base64 | tr -d '\n')"
  B64_USERNAME="$(printf '%s' kargo-bot | base64 | tr -d '\n')"
  B64_PASSWORD="$(printf '%s' "$token" | base64 | tr -d '\n')"
  local f
  for f in 01-project 02-credentials; do
    render_template "$ROOT_DIR/platform/kargo-project/$f.yaml" >"$dir/$f.yaml"
  done
  local prune_types='stages,warehouses,project-configs,analysis-templates,promotion-tasks,custom-promotion-steps'
  local args=(-f "$dir" --name "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG")
  [[ "$prune" != yes ]] || args+=(--prune "$prune_types")
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] akuity kargo apply -f <Project and git credentials>%s\n' "$([[ "$prune" == yes ]] && echo " --prune $prune_types")"
    sed 's/^/      | /' "$dir/01-project.yaml"
  else
    akuity kargo apply "${args[@]}"
  fi
}

# Checks the pieces every platform call needs and sets ORG, ARGO, KARGO
platform_preflight() {
  require_prefix
  [[ -x "$TOOLS_BIN/akuity" ]] || die "The akuity CLI is not installed in $TOOLS_BIN. Run: make tools"
  akuity_logged_in || die "You are not logged in to $AKUITY_SERVER_URL. Run: make login"
  ORG="$(akuity_org)"
  ARGO="$AKUITY_ARGOCD_INSTANCE"
  KARGO="$AKUITY_KARGO_INSTANCE"
  akuity argocd instance get "$ARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG" >/dev/null 2>&1 ||
    die "The Argo CD instance '$ARGO' does not exist. Run: make up"
  akuity kargo instance get "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG" >/dev/null 2>&1 ||
    die "The Kargo instance '$KARGO' does not exist. Run: make up"
}
