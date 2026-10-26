#!/usr/bin/env bash
# Checks that a step of the workshop did what it should. Read-only; prints one line per check and exits 1 when
# something is wrong, with a hint for each failure.
#
#   scripts/check.sh setup        the environment of phase 1: cluster, Gitea, the platform, the five apps, the Kargo project
#
# The labs add their own steps (1, 2, ...) in later phases.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools

STEP="${1:-}"
FAILS=0
good() { printf '%s ok %s %s\n' "$_C_GREEN" "$_C_RESET" "$1"; }
bad() { # bad <what is wrong> <what to try>
  printf '%sFAIL%s %s\n     -> %s\n' "$_C_RED" "$_C_RESET" "$1" "$2"
  FAILS=$((FAILS + 1))
}
section() { printf '\n%s\n' "$1"; }

# One line of a `akuity ... list` table ("ID NAME HEALTH") by name: prints the health
health_in() { awk -v n="$1" 'NR>1 && $2==n {print $3}'; }

check_setup() {
  local stage url code ver org h
  section "Cluster"
  if ! cluster_exists; then
    bad "the cluster '$CLUSTER_NAME' does not exist" "run: make up"
    return 0
  fi
  if kubectl wait --for=condition=Ready node --all --timeout=20s >/dev/null 2>&1; then
    good "the cluster node is ready"
  else
    bad "the cluster node is not ready" "give it a minute, or run: make status"
  fi

  section "Gitea"
  if git -c "http.extraHeader=Host: $(service_host gitea)$(port_suffix)" ls-remote --heads \
    "http://$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD@127.0.0.1:$HTTP_PORT/$GITEA_ORG/$GITEA_REPO.git" "$GITEA_BRANCH" 2>/dev/null |
    grep -q "refs/heads/$GITEA_BRANCH"; then
    good "the repository $GITEA_ORG/$GITEA_REPO exists at $(gitea_url)"
  else
    bad "the repository $GITEA_ORG/$GITEA_REPO is missing or empty" "run: make seed"
  fi

  section "Akuity Platform"
  if ! akuity_logged_in; then
    bad "you are not logged in to $AKUITY_SERVER_URL" "run: make login"
    return 0
  fi
  require_prefix
  org="$(akuity_org)"
  h="$(akuity argocd instance list --server "$AKUITY_SERVER_URL" --organization-name "$org" | health_in "$AKUITY_ARGOCD_INSTANCE")"
  if [[ "$h" == Healthy ]]; then good "Argo CD instance $AKUITY_ARGOCD_INSTANCE is Healthy"; else bad "Argo CD instance $AKUITY_ARGOCD_INSTANCE is '${h:-missing}'" "run: make up"; fi
  h="$(akuity argocd cluster list --instance-name "$AKUITY_ARGOCD_INSTANCE" --server "$AKUITY_SERVER_URL" --organization-name "$org" 2>/dev/null | health_in "$CLUSTER_NAME")"
  if [[ "$h" == Healthy ]]; then good "your cluster is connected to Argo CD and Healthy"; else bad "your cluster is '${h:-not connected}' in Argo CD" "run: make up"; fi
  h="$(akuity kargo instance list --server "$AKUITY_SERVER_URL" --organization-name "$org" | health_in "$AKUITY_KARGO_INSTANCE")"
  if [[ "$h" == Healthy ]]; then good "Kargo instance $AKUITY_KARGO_INSTANCE is Healthy"; else bad "Kargo instance $AKUITY_KARGO_INSTANCE is '${h:-missing}'" "run: make up"; fi
  h="$(akuity kargo agent list --instance-name "$AKUITY_KARGO_INSTANCE" --server "$AKUITY_SERVER_URL" --organization-name "$org" 2>/dev/null | health_in "$CLUSTER_NAME")"
  if [[ "$h" == Healthy ]]; then good "the Kargo agent in your cluster is Healthy"; else bad "the Kargo agent is '${h:-missing}'" "run: make up"; fi

  section "Kargo project"
  if kargo_login 2>/dev/null; then
    if kargo_cli get projects 2>/dev/null | awk -v p="$KARGO_PROJECT" '$1==p && $2=="True" {f=1} END {exit !f}'; then
      good "project $KARGO_PROJECT is ready"
    else
      bad "project $KARGO_PROJECT is missing or not ready" "run: make seed"
    fi
    if kargo_cli get repo-credentials --project "$KARGO_PROJECT" 2>/dev/null | grep -q "$(gitea_repo_url)"; then
      good "Kargo has the credentials to push to $(gitea_repo_url)"
    else
      bad "Kargo has no credentials for $(gitea_repo_url)" "run: make seed"
    fi
  else
    bad "could not log in to Kargo with the admin account" "run: make up, then open the Kargo URL from 'make urls' in a browser"
  fi

  section "The five applications"
  for stage in $STAGES; do
    url="$(service_url "guestbook-$stage")"
    ver=""
    code="$(curl -s -m 8 -o "$TOOLS_DIR/.page" -w '%{http_code}' --resolve "$(service_host "guestbook-$stage"):${HTTP_PORT}:127.0.0.1" "$url/" 2>/dev/null || true)"
    [[ "$code" != 200 ]] || ver="$(sed -n 's/.*id="version">\([^<]*\)<.*/\1/p' "$TOOLS_DIR/.page" | head -1)"
    if [[ "$code" == 200 && -n "$ver" ]]; then
      good "$stage answers at $url and runs version $ver"
    else
      bad "$stage does not answer at $url (HTTP ${code:-none})" "open Argo CD: the application guestbook-$stage should be Synced and Healthy. If it is not there, run: make seed"
    fi
  done
  rm -f "$TOOLS_DIR/.page"
}

case "$STEP" in
  setup) check_setup ;;
  "") die "Say which step: make check STEP=setup" ;;
  *) die "Unknown step '$STEP'. Known now: setup (the labs come in later phases)." ;;
esac

printf '\n'
if ((FAILS > 0)); then
  printf '%s%d check(s) failed.%s Follow the hints above and run the check again.\n' "$_C_RED" "$FAILS" "$_C_RESET"
  exit 1
fi
printf '%sAll good.%s\n' "$_C_GREEN" "$_C_RESET"
