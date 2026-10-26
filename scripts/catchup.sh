#!/usr/bin/env bash
# Does a lab for you, and every lab before it, so you can go on when you are behind. Safe to repeat: what is already
# done is skipped. The finished files are in steps/<N>/ (the same ones the lab asks you to write).
#
#   scripts/catchup.sh <N>
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools

TARGET="${1:-}"
[[ "$TARGET" =~ ^[0-9]+$ ]] || die "Say which lab: make catchup STEP=1"
cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
step() { printf '\n%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }

# wait_for <seconds> <what> <command...>: retries the command until it succeeds
wait_for() {
  local limit="$1" what="$2" end
  shift 2
  end=$((SECONDS + limit))
  while ((SECONDS < end)); do
    if "$@" >/dev/null 2>&1; then
      ok "$what"
      return 0
    fi
    sleep 4
  done
  die "Timed out waiting for: $what"
}

repo_tag() { gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/raw/env/$1/k8s/values.yaml" 2>/dev/null | sed -n 's/^ *tag: *//p' | head -1; }
stage_version() {
  curl -s -m 8 --resolve "$(service_host "guestbook-$1"):${HTTP_PORT}:127.0.0.1" "$(service_url "guestbook-$1")/" 2>/dev/null |
    sed -n 's/.*id="version">\([^<]*\)<.*/\1/p' | head -1
}
# (the output is read first: `grep -q` closing the pipe early would fail the pipeline under pipefail)
has_freight() {
  local out
  out="$(kargo_cli get freight --project "$KARGO_PROJECT" -o json 2>/dev/null || true)"
  grep -q -E "\"tag\": *\"$1\"" <<<"$out"
}
promotion_succeeded() {
  local out
  out="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage "$1" --no-headers 2>/dev/null || true)"
  grep -q 'Succeeded' <<<"$out"
}
# The name of the Freight with this image tag, once it is verified in the given Stage (empty until then)
freight_verified_in() { # <stage> <tag>
  kargo_cli get freight --project "$KARGO_PROJECT" \
    -o jsonpath='{range .items[*]}{.metadata.name} {.images[0].tag} {.status.verifiedIn.'"$1"'.verifiedAt}{"\n"}{end}' 2>/dev/null |
    awk -v tag="$2" '$2 == tag && NF >= 3 {print $1; exit}' || true
}
freight_is_verified() { [[ -n "$(freight_verified_in "$1" "$2")" ]]; }
stage_runs() { [[ "$(stage_version "$1")" == "$2" ]]; } # stage_runs <stage> <version>

# Renders steps/<N>/<file> with this machine's settings and applies it with the kargo CLI
apply_step_file() { # <N> <file>
  export GITEA_REPO_URL CLUSTER_IMAGE_REPO
  GITEA_REPO_URL="$(gitea_repo_url)"
  CLUSTER_IMAGE_REPO="$(image_repo_cluster)"
  render_template "$ROOT_DIR/steps/$1/$2" >"$WORK/$2"
  kargo_cli apply -f "$WORK/$2" >/dev/null
  ok "applied steps/$1/$2"
}

catchup_1() {
  step "Lab 1: the first release, the dev Stage, the first promotion"
  "$LIB_DIR/../release.sh" 1.0.0
  wait_for 120 "Freight with the image 1.0.0 was created" has_freight 1.0.0
  apply_step_file 1 stage-dev.yaml
  if [[ "$(repo_tag dev)" == "1.0.0" ]] && promotion_succeeded dev; then
    ok "dev already has 1.0.0: nothing to promote"
  else
    kargo_cli promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    ok "promotion to dev started"
    wait_for 240 "the promotion to dev succeeded" promotion_succeeded dev
  fi
  wait_for 240 "dev runs 1.0.0" stage_runs dev 1.0.0
}

catchup_2() {
  step "Lab 2: the staging Stage, auto-promotion on dev, release 1.1.0, staging promoted by hand"
  apply_step_file 2 stage-staging.yaml
  apply_step_file 2 project-config.yaml
  "$LIB_DIR/../release.sh" 1.1.0
  wait_for 120 "Freight with the image 1.1.0 was created" has_freight 1.1.0
  # dev promotes by itself now; staging is the gate
  wait_for 300 "dev runs 1.1.0 (promoted by Kargo)" stage_runs dev 1.1.0
  if [[ "$(repo_tag staging)" == "1.1.0" ]]; then
    ok "staging already has 1.1.0: nothing to promote"
  else
    # the page of dev can show 1.1.0 a few seconds before Kargo marks the Freight as verified in dev: staging only takes
    # Freight that is, so wait for that and name the Freight instead of letting Kargo choose
    wait_for 120 "Freight 1.1.0 is verified in dev" freight_is_verified dev 1.1.0
    kargo_cli promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev 1.1.0)" --stage staging >/dev/null
    ok "promotion to staging started"
    wait_for 240 "the promotion to staging succeeded" promotion_succeeded staging
  fi
  wait_for 240 "staging runs 1.1.0" stage_runs staging 1.1.0
}

kargo_login
for n in $(seq 1 "$TARGET"); do
  case "$n" in
    1) catchup_1 ;;
    2) catchup_2 ;;
    *) die "Lab $n is not written yet." ;;
  esac
done
printf '\n%sCaught up with lab %s.%s Run: make check STEP=%s\n' "$_C_GREEN" "$TARGET" "$_C_RESET" "$TARGET"
