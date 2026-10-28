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
  local prune_types='stages,warehouses,project-configs,analysis-templates,promotion-tasks,custom-promotion-steps,event-routers,message-channels'
  local args=(-f "$dir" --name "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG")
  [[ "$prune" != yes ]] || args+=(--prune "$prune_types")
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] akuity kargo apply -f <Project and git credentials>%s\n' "$([[ "$prune" == yes ]] && echo " --prune $prune_types")"
    sed 's/^/      | /' "$dir/01-project.yaml"
  else
    if [[ "$prune" == yes ]]; then
      # A channel cannot be deleted while a router still points to it: routers go first, on their own
      akuity kargo apply -f "$dir" --name "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG" --prune event-routers
      # (the platform needs a few seconds to see that the routers are gone)
      local try
      for try in 1 2 3 4 5 6; do
        akuity kargo apply "${args[@]}" && return 0
        ((try == 6)) || sleep 5
      done
      return 1
    fi
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

# --- The Promotion Controller (needs platform_preflight first) ----------------------------------------------------------

promotion_controller_enabled() {
  local out
  out="$(akuity kargo instance get "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG" -o yaml 2>/dev/null || true)"
  grep -q '^  promoControllerEnabled: true' <<<"$out"
}

# set_promotion_controller on|off: applies the instance specification with that one field changed, and waits for the controller
set_promotion_controller() {
  local want="$1" dir doc value=false
  [[ "$want" != on ]] || value=true
  if [[ "$value" == true ]] && promotion_controller_enabled; then
    ok "the Promotion Controller is already on"
    return 0
  fi
  if [[ "$value" == false ]] && ! promotion_controller_enabled; then
    ok "the Promotion Controller is already off"
    return 0
  fi
  dir="$(mktemp -d)"
  # the first document of the export is the instance itself; the field goes right under kargoInstanceSpec
  doc="$(akuity kargo export "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG")"
  doc="$(awk '/^---$/ {exit} {print}' <<<"$doc")"
  printf '%s\n' "$doc" | awk -v v="$value" '
    /^    promoControllerEnabled:/ {next}
    {print}
    /^  kargoInstanceSpec:/ {print "    promoControllerEnabled: " v}
  ' >"$dir/kargo-instance.yaml"
  akuity kargo apply -f "$dir" --name "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG" >/dev/null
  rm -rf "$dir"
  local _
  for _ in $(seq 1 18); do
    sleep 5
    if [[ "$value" == true ]]; then
      kubectl -n "${AGENT_NS:-akuity}" get deploy "kargo-promotion-controller-$CLUSTER_NAME" -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qx 1 && break
    else
      kubectl -n "${AGENT_NS:-akuity}" get deploy "kargo-promotion-controller-$CLUSTER_NAME" >/dev/null 2>&1 || break
    fi
  done
  ok "the Promotion Controller is $want"
}
