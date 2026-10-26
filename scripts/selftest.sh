#!/usr/bin/env bash
# End-to-end ingress test: deploys a temporary nginx with an Ingress for selftest.${WORKSHOP_DOMAIN}, requests
# it from this machine and from a pod with the same URL, then removes everything.
# Called by `scripts/up.sh --selftest`; can also be run alone.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools
cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"

NS="workshop-selftest"
HOST="$(service_host selftest)"
cleanup() { kubectl delete namespace "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels: {app: web}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
        - name: web
          image: ${SELFTEST_IMAGE}
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: {app: web}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
spec:
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port: {number: 80}
EOF
kubectl -n "$NS" rollout status deployment/web --timeout=180s >/dev/null
ok "temporary app is running"

wait_for() { # <label> <command...>: retries until the command prints 200
  local label="$1" got=""
  shift
  for _ in $(seq 1 20); do
    got="$("$@" 2>/dev/null || true)"
    [[ "$got" == 200 ]] && {
      ok "$label: HTTP 200"
      return 0
    }
    sleep 2
  done
  die "$label: expected HTTP 200, got '${got:-no answer}'"
}

from_host() { curl -s -o /dev/null -m 5 -w '%{http_code}' --resolve "$HOST:${HTTP_PORT}:127.0.0.1" "http://$HOST:${HTTP_PORT}/"; }
from_pod() {
  kubectl run "curl-$RANDOM" --rm -i --quiet --restart=Never --image="$CURL_IMAGE" -- \
    curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$HOST:${HTTP_PORT}/"
}

wait_for "http://$HOST:${HTTP_PORT}/ from this machine" from_host
wait_for "http://$HOST:${HTTP_PORT}/ from inside the cluster" from_pod

# The Ingress must carry an address, or Argo CD would show the Application as Progressing forever
addr="$(kubectl -n "$NS" get ingress web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
[[ -n "$addr" ]] || die "The Ingress has no status.loadBalancer address (Argo CD would never see it as Healthy)"
ok "the Ingress reports address $addr"
