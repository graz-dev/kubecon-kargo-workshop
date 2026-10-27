#!/usr/bin/env bash
# Makes the workshop work with little or no network: images are pulled into Docker on this machine ahead of time
# (at home, on a good connection) and loaded into the kind node when the cluster is created.
#
#   scripts/prefetch.sh [pull|load|all]    pull: docker pull everything · load: kind load what is already pulled · all (default): both
#
# The list: manifests/prefetch-images.txt, the helper images of versions.env, every guestbook version of the
# catalog, and .tools/images-seen.txt (what the last `make up` really used, agents included).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_docker

MODE="${1:-all}"
case "$MODE" in pull | load | all) ;; -h | --help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;; *) die "Unknown mode '$MODE' (pull, load or all)" ;; esac

images() {
  {
    grep -v -E '^\s*(#|$)' "$ROOT_DIR/manifests/prefetch-images.txt"
    printf '%s\n' "$CURL_IMAGE" "$SELFTEST_IMAGE"
    local v
    for v in $(prepublished_versions); do printf '%s:%s\n' "$(image_repo_cluster)" "$v"; done
    # what the last `make up` used, minus Kubernetes' own images: those are already inside the kind node image
    if [[ -f "$TOOLS_DIR/images-seen.txt" ]]; then grep -v -E '^(registry\.k8s\.io/|docker\.io/kindest/)' "$TOOLS_DIR/images-seen.txt" || true; fi
  } | sort -u
}

present() { docker image inspect "$1" >/dev/null 2>&1; }

if [[ "$MODE" == pull || "$MODE" == all ]]; then
  total=0 pulled=0 failed=0
  while IFS= read -r img; do
    total=$((total + 1))
    if present "$img"; then
      pulled=$((pulled + 1))
    elif docker pull -q "$img" >/dev/null 2>&1; then
      pulled=$((pulled + 1))
      ok "pulled $img"
    else
      failed=$((failed + 1))
      warn "could not pull $img"
    fi
  done < <(images)
  info "$pulled of $total images are on this machine ($failed could not be pulled)"
fi

if [[ "$MODE" == load || "$MODE" == all ]]; then
  if cluster_exists; then
    loaded=0
    while IFS= read -r img; do
      # `kind load docker-image` fails on multi-platform images whose other platforms are not on this machine
      # ("content digest ... not found"): the same import without --all-platforms works
      if present "$img" && docker save "$img" 2>/dev/null |
        docker exec --privileged -i "${CLUSTER_NAME}-control-plane" ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs - >/dev/null 2>&1; then
        loaded=$((loaded + 1))
      fi
    done < <(images)
    info "$loaded images loaded into the cluster '$CLUSTER_NAME'"
  elif [[ "$MODE" == load ]]; then
    die "Cluster '$CLUSTER_NAME' does not exist."
  fi
fi
