#!/usr/bin/env bash
# Creates (or updates) the local part of the workshop environment. Idempotent: running it twice is safe.
#   1. kind cluster with Traefik's NodePort published on HTTP_PORT (loopback)
#   2. Traefik (Helm, pinned)
#   3. CoreDNS answers *.${WORKSHOP_DOMAIN} with Traefik's ClusterIP, so the same URL works inside the cluster
#   4. checks: a request to Traefik from the host and from a pod
#   5. connects the cluster to the Akuity Platform (scripts/platform-up.sh), unless SKIP_PLATFORM=1
#
#   scripts/up.sh [--selftest]      --selftest (or SELFTEST=1) also deploys a temporary app and routes to it
#                                   SKIP_PLATFORM=1 builds the local part only; DRY_RUN=1 shows what the platform part would create
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

SELFTEST="${SELFTEST:-0}"
for arg in "$@"; do
  case "$arg" in
    --selftest) SELFTEST=1 ;;
    -h | --help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument '$arg'" ;;
  esac
done

# The platform part needs the prefix: stop now rather than after the cluster is built
if [[ "${SKIP_PLATFORM:-0}" != 1 ]]; then
  require_prefix
fi

START="$(date +%s)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
step() { printf '\n%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }

# --- 0. Prerequisites ----------------------------------------------------------------
require_docker
"$LIB_DIR/../tools.sh" install >/dev/null
require_tools

# --- 1. Cluster ----------------------------------------------------------------------
CLUSTER_CREATED=0
create_cluster() {
  local bound want
  if cluster_exists; then
    want="${BIND_ADDRESS}:${HTTP_PORT}"
    bound="$(docker port "${CLUSTER_NAME}-control-plane" "${TRAEFIK_NODE_PORT}/tcp" 2>/dev/null | head -1 || true)"
    if [[ -n "$bound" && "$bound" != "$want" ]]; then
      die "Cluster '$CLUSTER_NAME' publishes $bound but the settings ask for $want. Run 'make down' and then 'make up'."
    fi
    kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
    ok "cluster '$CLUSTER_NAME' already exists"
    return 0
  fi
  if port_in_use "$HTTP_PORT"; then
    die "Port $HTTP_PORT is already in use on this machine. Free it, or set HTTP_PORT=8080 in workshop.env."
  fi
  mkdir -p "$TOOLS_DIR"
  render_template "$ROOT_DIR/kind/cluster.yaml" >"$WORK/kind.yaml"
  info "Creating the kind cluster '$CLUSTER_NAME' ($KIND_NODE_IMAGE)"
  kind create cluster --config "$WORK/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 180s
  CLUSTER_CREATED=1
}

step "Cluster"
create_cluster
kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null
ok "node ready"

# Images pulled earlier by `make prefetch` are loaded now, so the installs below do not download them again
if [[ "$CLUSTER_CREATED" == 1 ]] && docker image inspect "$CURL_IMAGE" >/dev/null 2>&1; then
  step "Prefetched images"
  "$LIB_DIR/../prefetch.sh" load
fi

# --- 2. Traefik ----------------------------------------------------------------------
step "Traefik $TRAEFIK_CHART_VERSION"
render_template "$ROOT_DIR/manifests/traefik-values.yaml" >"$WORK/traefik-values.yaml"
helm upgrade --install traefik traefik \
  --repo "$TRAEFIK_CHART_REPO" --version "$TRAEFIK_CHART_VERSION" \
  --namespace "$TRAEFIK_NAMESPACE" --create-namespace \
  --values "$WORK/traefik-values.yaml" --wait --timeout 3m >/dev/null
ok "traefik deployed"

# --- 3. CoreDNS ----------------------------------------------------------------------
# A zone block for WORKSHOP_DOMAIN answers every name with Traefik's ClusterIP. A "template" answer is used
# (not "rewrite") because the answer must carry the name that was asked, or resolvers ignore it.
configure_coredns() {
  local ip current base desired
  ip="$(kubectl -n "$TRAEFIK_NAMESPACE" get svc traefik -o jsonpath='{.spec.clusterIP}')"
  [[ -n "$ip" ]] || die "Could not read the ClusterIP of the traefik Service"
  current="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
  base="$(printf '%s\n' "$current" | awk '/# kargo-workshop:begin/{skip=1} !skip{print} /# kargo-workshop:end/{skip=0}')"
  desired="$(
    printf '%s\n\n' "$base"
    cat <<EOF
# kargo-workshop:begin
${WORKSHOP_DOMAIN}:53 {
    errors
    template IN A ${WORKSHOP_DOMAIN} {
        answer "{{ .Name }} 60 IN A ${ip}"
    }
    template IN AAAA ${WORKSHOP_DOMAIN} {
        rcode NOERROR
    }
}
# kargo-workshop:end
EOF
  )"
  if [[ "$current" == "$desired" ]]; then
    ok "coredns already answers *.${WORKSHOP_DOMAIN} with ${ip}"
    return 0
  fi
  printf '%s\n' "$desired" >"$WORK/Corefile"
  kubectl -n kube-system create configmap coredns --from-file=Corefile="$WORK/Corefile" --dry-run=client -o yaml |
    kubectl apply --server-side --force-conflicts --field-manager=kargo-workshop -f - >/dev/null
  kubectl -n kube-system rollout restart deployment/coredns >/dev/null
  kubectl -n kube-system rollout status deployment/coredns --timeout=120s >/dev/null
  ok "coredns now answers *.${WORKSHOP_DOMAIN} with ${ip}"
}

step "CoreDNS"
configure_coredns

# --- 4. Checks -----------------------------------------------------------------------
# Traefik answers 404 for a host without a route: reaching it proves the port path end to end.
http_code_from_host() { # <host> -> status code (resolves the host to 127.0.0.1 itself, so it does not need public DNS)
  curl -s -o /dev/null -m 5 -w '%{http_code}' --resolve "$1:${HTTP_PORT}:127.0.0.1" "http://$1:${HTTP_PORT}/" 2>/dev/null || true
}

http_code_from_pod() { # <host> -> status code, requested from inside the cluster with the public URL
  kubectl run "curl-$RANDOM" --rm -i --quiet --restart=Never --image="$CURL_IMAGE" -- \
    curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$1:${HTTP_PORT}/" 2>/dev/null || true
}

expect_code() { # <label> <expected> <command...>
  local label="$1" want="$2" got=""
  shift 2
  for _ in $(seq 1 15); do
    got="$("$@")"
    [[ "$got" == "$want" ]] && {
      ok "$label: HTTP $got"
      return 0
    }
    sleep 2
  done
  die "$label: expected HTTP $want, got '${got:-no answer}'"
}

step "Checks"
PROBE="$(service_host doctor-probe)"
# (404 is the expected answer: Traefik is up and has no route for this made-up host, because no app is deployed yet)
expect_code "Traefik answers from this machine ($PROBE:${HTTP_PORT}); 404 = no app behind it yet, as expected" 404 http_code_from_host "$PROBE"
expect_code "Traefik answers from inside the cluster at the same URL (404 as expected)" 404 http_code_from_pod "$PROBE"

if [[ "$SELFTEST" == 1 ]]; then
  step "Self-test: route to a temporary app"
  "$LIB_DIR/../selftest.sh"
fi

# --- 5. Akuity Platform --------------------------------------------------------------
if [[ "${SKIP_PLATFORM:-0}" != 1 ]]; then
  step "Akuity Platform"
  [[ "${DRY_RUN:-0}" != 1 ]] || info "DRY_RUN applies to the platform only: the local cluster above was really created or checked"
  if ! akuity_logged_in; then
    printf '%sThe local environment is ready%s in %ss, but you are not logged in to the Akuity Platform.\n' "$_C_YELLOW" "$_C_RESET" "$(($(date +%s) - START))"
    printf 'Run: make login   and then: make up\n'
    exit 1
  fi
  "$LIB_DIR/../platform-up.sh"
fi

# Remember which images this cluster used, so that `make prefetch` can fetch them next time
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' |
  sort -u >"$TOOLS_DIR/images-seen.txt" || true

# --- Summary -------------------------------------------------------------------------
printf '\n%sThe local environment is ready%s in %ss.\n' "$_C_GREEN" "$_C_RESET" "$(($(date +%s) - START))"
printf 'Use kubectl with this cluster:  export KUBECONFIG=%s\n' "${KUBECONFIG#"$PWD"/}"
printf 'Gitea and the apps will be at:  %s\n' "$(service_url gitea)"
