#!/usr/bin/env bash
# Prints the URL of every UI. The local ones are rendered from workshop.env; it does not need a running cluster.
# Kargo and Argo CD are hosted on the Akuity Platform: their instance URLs are shown in the platform UI.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

if [[ -x "$TOOLS_BIN/akuity" && -z "$(prefix_problem)" ]] && akuity_logged_in; then
  org="$(akuity_org)"
  printf '%-26s %s\n' "Kargo" "$(akuity_instance_url kargo "$AKUITY_KARGO_INSTANCE" "$org")"
  printf '%-26s %s\n' "Argo CD" "$(akuity_instance_url argocd "$AKUITY_ARGOCD_INSTANCE" "$org")"
  if [[ -f "$ADMIN_ENV" ]]; then
    printf '%-26s %s\n' "  login (both)" "admin / $(sed -n 's/^ADMIN_PASSWORD=//p' "$ADMIN_ENV")"
  fi
else
  printf '%-26s %s\n' "Kargo / Argo CD" "$AKUITY_SERVER_URL   (set WORKSHOP_PREFIX and run make login to see your instance URLs)"
fi
# Gitea and the apps arrive with phase P1.4: say so while they are not in the cluster
NOTE=""
if [[ -x "$TOOLS_BIN/kubectl" ]] && cluster_exists && ! kubectl get namespace gitea >/dev/null 2>&1; then
  NOTE="   [not installed yet: comes with phase P1.4]"
elif ! cluster_exists 2>/dev/null; then
  NOTE="   [no cluster yet: make up]"
fi
printf '%-26s %s\n' "Gitea" "$(service_url gitea)   ($GITEA_USER / $GITEA_PASSWORD)$NOTE"
for stage in $STAGES; do
  printf '%-26s %s%s\n' "guestbook ($stage)" "$(service_url "guestbook-$stage")" "$NOTE"
done
