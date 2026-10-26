#!/usr/bin/env bash
# Connects the kind cluster to the Akuity Platform. Idempotent: running it again only fills in what is missing.
#   1. Argo CD instance (+ the kind cluster as a managed cluster, + repo server / ApplicationSet delegates)
#   2. the Argo CD agent in the kind cluster
#   3. Kargo instance
#   4. a self-hosted Kargo agent linked to that Argo CD instance, installed in the kind cluster
# Everything goes through the akuity CLI; the CLI's global configuration is never changed.
# Needs: `make login` done, and the cluster created by scripts/up.sh.
#
#   scripts/platform-up.sh        (DRY_RUN=1 prints what it would create and creates nothing)
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools
[[ -x "$TOOLS_BIN/akuity" ]] || die "The akuity CLI is not installed in $TOOLS_BIN. Run: make tools"

DRY_RUN="${DRY_RUN:-0}"
CONTEXT="kind-${CLUSTER_NAME}"
AGENT_NS=akuity
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
step() { printf '\n%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }

require_prefix
akuity_logged_in || die "You are not logged in to $AKUITY_SERVER_URL. Run: make login"
cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"
ORG="$(akuity_org)"
AKUITY_EMAIL="$(akuity_email)" # written into the description of what we create: it says whose instance it is
export AKUITY_EMAIL
ensure_admin_credentials
ARGO="$AKUITY_ARGOCD_INSTANCE"
KARGO="$AKUITY_KARGO_INSTANCE"
AGENT="$CLUSTER_NAME" # the Kargo agent and the Argo CD cluster agent both carry the name of the cluster

# akuity with the server and the organization named explicitly
ak() { akuity "$@" --server "$AKUITY_SERVER_URL" --organization-name "$ORG"; }
# Runs a command that creates or changes something on the platform (or only prints it in a dry run)
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}
# Health of an instance by name ("" when it does not exist). The list is a table: ID NAME HEALTH
health_of() { ak "$1" instance list 2>/dev/null | awk -v n="$2" 'NR>1 && $2==n {print $3}'; }

# Stops when an existing instance does not mention the logged-in account in its description: in a shared
# organization that means it belongs to someone else (we write "Kargo workshop (<e-mail>)" when we create one).
check_owner() { # <argocd|kargo> <name>
  [[ "$DRY_RUN" == 1 ]] && return 0
  ak "$1" instance get "$2" -o json 2>/dev/null | grep -qF "$AKUITY_EMAIL" ||
    die "The $1 instance '$2' exists but was not created by $AKUITY_EMAIL (its description does not mention it). Another attendee probably uses the same WORKSHOP_PREFIX: choose a different one in workshop.env."
}

wait_healthy() { # <argocd|kargo> <name>
  local kind="$1" name="$2" h="" deadline=$((SECONDS + 300))
  [[ "$DRY_RUN" == 1 ]] && return 0
  while ((SECONDS < deadline)); do
    h="$(health_of "$kind" "$name")"
    [[ "$h" == Healthy ]] && {
      ok "$kind instance '$name' is Healthy"
      return 0
    }
    sleep 5
  done
  die "$kind instance '$name' is not Healthy after 5 minutes (last state: '${h:-missing}'). Look at it in the platform UI."
}

# Waits until every Deployment and StatefulSet in the agents' namespace has rolled out
wait_agents() {
  local deadline=$((SECONDS + 300)) objs obj bad
  [[ "$DRY_RUN" == 1 ]] && return 0
  while ((SECONDS < deadline)); do
    objs="$(kubectl -n "$AGENT_NS" get deployments,statefulsets -o name 2>/dev/null || true)"
    bad=0
    [[ -n "$objs" ]] || bad=1
    for obj in $objs; do
      kubectl -n "$AGENT_NS" rollout status "$obj" --timeout=10s >/dev/null 2>&1 || bad=1
    done
    ((bad == 0)) && {
      ok "agents in namespace '$AGENT_NS' are running"
      return 0
    }
    sleep 5
  done
  kubectl -n "$AGENT_NS" get pods || true
  die "The agents did not become ready in 5 minutes. Check: kubectl -n $AGENT_NS get pods (KUBECONFIG=${KUBECONFIG#"$PWD"/})"
}

[[ "$DRY_RUN" != 1 ]] || printf '%sDRY RUN%s: reading from the platform, creating nothing.\n' "$_C_YELLOW" "$_C_RESET"
info "organization: $ORG  ·  server: $AKUITY_SERVER_URL  ·  cluster: $CLUSTER_NAME"
info "prefix: $WORKSHOP_PREFIX  ·  Argo CD instance: $ARGO ($AKUITY_ARGOCD_VERSION)  ·  Kargo instance: $KARGO ($AKUITY_KARGO_VERSION)  ·  Kargo agent: $AGENT"

# --- 0. The pinned versions must be selectable ---------------------------------------------
step "Versions"
# (the lists are captured first: `grep -q` closing the pipe early would fail the pipeline under pipefail)
argo_versions="$(akuity argocd instance versions --server "$AKUITY_SERVER_URL" | awk 'NR>1 {print $1}')"
kargo_versions="$(akuity kargo instance versions --server "$AKUITY_SERVER_URL" | awk 'NR>1 {print $1}')"
grep -qx "$AKUITY_ARGOCD_VERSION" <<<"$argo_versions" ||
  die "Argo CD $AKUITY_ARGOCD_VERSION is not offered by the platform. See: akuity argocd instance versions"
grep -qx "$AKUITY_KARGO_VERSION" <<<"$kargo_versions" ||
  die "Kargo $AKUITY_KARGO_VERSION is not offered by the platform. See: akuity kargo instance versions"
ok "Argo CD $AKUITY_ARGOCD_VERSION and Kargo $AKUITY_KARGO_VERSION are available"

# --- 1. Argo CD instance, cluster, agent and delegates -------------------------------------
# Applied twice: the platform rejects delegates that name a cluster which does not exist yet, so the first
# apply declares the instance and the cluster only; the delegates come once the agent is installed.
step "Argo CD instance '$ARGO' and cluster '$CLUSTER_NAME'"
mkdir -p "$WORK/argocd-full" "$WORK/argocd-base"
render_template "$ROOT_DIR/platform/argocd.yaml" >"$WORK/argocd-full/argocd.yaml"
awk '/# delegates:begin/ {skip=1; next} /# delegates:end/ {skip=0; next} !skip' "$WORK/argocd-full/argocd.yaml" |
  sed 's/^  instanceSpec:$/  instanceSpec: {}/' >"$WORK/argocd-base/argocd.yaml"
# The admin account (off by default) and its password, in both applies
for f in argocd-cm argocd-secret; do
  render_template "$ROOT_DIR/platform/$f.yaml" >"$WORK/argocd-full/$f.yaml"
  cp "$WORK/argocd-full/$f.yaml" "$WORK/argocd-base/$f.yaml"
done
if [[ -n "$(health_of argocd "$ARGO")" ]]; then
  ok "instance exists ($(health_of argocd "$ARGO")); applying the specification again keeps it as declared"
  check_owner argocd "$ARGO"
else
  info "creating the instance (this takes a minute or two)"
fi
if [[ "$DRY_RUN" == 1 ]]; then
  printf '  [dry-run] akuity argocd apply -f <instance, cluster, argocd-cm with admin enabled, argocd-secret with the password hash> --organization-name %s\n' "$ORG"
  sed 's/^/      | /' "$WORK/argocd-base/argocd.yaml"
else
  ak argocd apply -f "$WORK/argocd-base"
fi
wait_healthy argocd "$ARGO"

step "Argo CD agent in the kind cluster"
run akuity argocd cluster install-agent --server "$AKUITY_SERVER_URL" --organization-name "$ORG" \
  --instance-name "$ARGO" --kubeconfig "$KUBECONFIG" --context "$CONTEXT" "$CLUSTER_NAME"
wait_agents

step "Repo server and ApplicationSet delegates (they run in the kind cluster)"
if [[ "$DRY_RUN" == 1 ]]; then
  printf '  [dry-run] akuity argocd apply -f <the same file, now with the delegates> --organization-name %s\n' "$ORG"
  sed -n '/delegates:begin/,/delegates:end/p' "$WORK/argocd-full/argocd.yaml" | sed 's/^/      | /'
else
  ak argocd apply -f "$WORK/argocd-full"
fi
wait_healthy argocd "$ARGO"

# --- 2. Kargo instance and self-hosted agent -----------------------------------------------
step "Kargo instance '$KARGO'"
if [[ -n "$(health_of kargo "$KARGO")" ]]; then
  ok "instance exists ($(health_of kargo "$KARGO"))"
  check_owner kargo "$KARGO"
else
  run akuity kargo instance create --server "$AKUITY_SERVER_URL" --organization-name "$ORG" \
    --version "$AKUITY_KARGO_VERSION" --description "Kargo workshop ($AKUITY_EMAIL)" "$KARGO"
fi
wait_healthy kargo "$KARGO"

step "Kargo admin account"
mkdir -p "$WORK/kargo"
for f in kargo-cm kargo-secret; do
  render_template "$ROOT_DIR/platform/$f.yaml" >"$WORK/kargo/$f.yaml"
done
if [[ "$DRY_RUN" == 1 ]]; then
  printf '  [dry-run] akuity kargo apply -f <kargo-cm.yaml and kargo-secret.yaml> --name %s\n' "$KARGO"
  sed 's/^/      | /' "$WORK/kargo/kargo-cm.yaml"
else
  ak kargo apply -f "$WORK/kargo" --name "$KARGO"
fi

step "Kargo agent '$AGENT' (self-hosted, linked to Argo CD '$ARGO')"
run akuity kargo agent create --server "$AKUITY_SERVER_URL" --organization-name "$ORG" \
  --instance-name "$KARGO" --self-hosted --akuity-argocd-name "$ARGO" --default-shard --upsert "$AGENT"
run akuity kargo agent install --server "$AKUITY_SERVER_URL" --organization-name "$ORG" \
  --instance-name "$KARGO" --kubeconfig "$KUBECONFIG" --context "$CONTEXT" "$AGENT"
wait_agents

# --- Summary -------------------------------------------------------------------------------
if [[ "$DRY_RUN" != 1 ]]; then
  step "On the platform"
  printf 'Argo CD clusters\n'
  ak argocd cluster list --instance-name "$ARGO"
  printf '\nKargo agents\n'
  ak kargo agent list --instance-name "$KARGO"
  printf '\n%sThe cluster is connected to the Akuity Platform.%s\n' "$_C_GREEN" "$_C_RESET"
  printf '  Argo CD: %s\n  Kargo:   %s\n' "$(akuity_instance_url argocd "$ARGO" "$ORG")" "$(akuity_instance_url kargo "$KARGO" "$ORG")"
  printf '  Log in with:  admin  /  %s   (kept in %s)\n' "$ADMIN_PASSWORD" "${ADMIN_ENV#"$PWD"/}"
fi
