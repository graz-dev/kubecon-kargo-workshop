#!/usr/bin/env bash
# Shows the state of the local environment. Read-only.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_docker
require_tools

if ! cluster_exists; then
  printf 'Cluster %s: not created. Run: make up\n' "$CLUSTER_NAME"
  exit 0
fi

kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
printf 'Cluster:    %s (kubectl: export KUBECONFIG=%s)\n' "$CLUSTER_NAME" "${KUBECONFIG#"$PWD"/}"
printf 'Ingress:    %s (published on %s:%s)\n' "$(service_url "<name>")" "$BIND_ADDRESS" "$HTTP_PORT"
printf '\nNodes\n'
kubectl get nodes -o wide
printf '\nPods\n'
kubectl get pods --all-namespaces
printf '\nMemory of the node container\n'
docker stats --no-stream --format '  {{.Name}}  {{.MemUsage}}  cpu {{.CPUPerc}}' "${CLUSTER_NAME}-control-plane"

printf '\nAkuity Platform (%s)\n' "$AKUITY_SERVER_URL"
if [[ -n "$(prefix_problem)" ]]; then
  printf '  %s\n' "$(prefix_problem)"
elif [[ -x "$TOOLS_BIN/akuity" ]] && akuity_logged_in; then
  org="$(akuity_org)"
  printf '  organization %s\n' "$org"
  printf '  Argo CD instance %s: %s\n' "$AKUITY_ARGOCD_INSTANCE" "$(akuity argocd instance list --server "$AKUITY_SERVER_URL" --organization-name "$org" | awk -v n="$AKUITY_ARGOCD_INSTANCE" 'NR>1 && $2==n {print $3}' | grep . || echo 'not created')"
  printf '  Argo CD URL: %s\n  Kargo URL:   %s\n' "$(akuity_instance_url argocd "$AKUITY_ARGOCD_INSTANCE" "$org")" "$(akuity_instance_url kargo "$AKUITY_KARGO_INSTANCE" "$org")"
  printf '  Kargo instance %s: %s\n' "$AKUITY_KARGO_INSTANCE" "$(akuity kargo instance list --server "$AKUITY_SERVER_URL" --organization-name "$org" | awk -v n="$AKUITY_KARGO_INSTANCE" 'NR>1 && $2==n {print $3}' | grep . || echo 'not created')"
else
  printf '  not logged in (make login)\n'
fi
