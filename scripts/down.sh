#!/usr/bin/env bash
# Deletes the kind cluster and our private kubeconfig. Safe to run when nothing exists.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

[[ -x "$TOOLS_BIN/kind" ]] || die "kind is not installed in $TOOLS_BIN. Run: make tools"
require_docker

if cluster_exists; then
  kind delete cluster --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG"
  ok "cluster '$CLUSTER_NAME' deleted"
else
  ok "cluster '$CLUSTER_NAME' does not exist: nothing to do"
fi
rm -f "$KUBECONFIG"
