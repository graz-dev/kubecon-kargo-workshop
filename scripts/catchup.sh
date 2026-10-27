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

catchup_3() {
  step "Lab 3: the prod gate, the three regions, release 1.2.0 all the way to production"
  apply_step_file 3 stage-prod.yaml
  apply_step_file 3 stage-prod-regions.yaml
  apply_step_file 3 project-config.yaml
  "$LIB_DIR/../release.sh" 1.2.0
  wait_for 120 "Freight with the image 1.2.0 was created" has_freight 1.2.0
  wait_for 300 "dev runs 1.2.0 (promoted by Kargo)" stage_runs dev 1.2.0
  if [[ "$(repo_tag staging)" == "1.2.0" ]]; then
    ok "staging already has 1.2.0: nothing to promote"
  else
    wait_for 120 "Freight 1.2.0 is verified in dev" freight_is_verified dev 1.2.0
    kargo_cli promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev 1.2.0)" --stage staging >/dev/null
    ok "promotion to staging started"
  fi
  wait_for 240 "staging runs 1.2.0" stage_runs staging 1.2.0
  if [[ "$(repo_tag prod-emea)" == "1.2.0" ]]; then
    ok "production already has 1.2.0: nothing to promote"
  else
    wait_for 120 "Freight 1.2.0 is verified in staging" freight_is_verified staging 1.2.0
    kargo_cli promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in staging 1.2.0)" --stage prod >/dev/null
    ok "promotion to prod started"
  fi
  # the three regions follow prod by themselves
  for region in prod-amer-east prod-amer-west prod-emea; do
    wait_for 300 "$region runs 1.2.0" stage_runs "$region" 1.2.0
  done
}

# True when the dev Stage reports a failed verification
dev_verification_failed() {
  local out
  out="$(kargo_cli get stages --project "$KARGO_PROJECT" --no-headers 2>/dev/null || true)"
  grep -q -E '^dev .*(assessed Failed|VerificationFailed)' <<<"$out"
}

catchup_4() {
  step "Lab 4: verification, the failed 1.3.0, the rollback, the hold and the fix 1.3.1"
  apply_step_file 4 analysis.yaml
  apply_step_file 4 stage-dev.yaml
  apply_step_file 4 stage-staging.yaml
  if has_freight 1.3.0; then
    ok "1.3.0 was released already"
  else
    "$LIB_DIR/../release.sh" 1.3.0
    wait_for 120 "Freight with the image 1.3.0 was created" has_freight 1.3.0
    wait_for 300 "dev took 1.3.0" stage_runs dev 1.3.0
    wait_for 240 "the check of dev failed for 1.3.0" dev_verification_failed
  fi
  if stage_runs dev 1.3.0; then
    # the rollback: promote the Freight that was there before
    kargo_cli promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev 1.2.0)" --stage dev >/dev/null
    ok "rollback of dev to 1.2.0 started"
    wait_for 240 "dev runs 1.2.0 again" stage_runs dev 1.2.0
  fi
  "$LIB_DIR/../release.sh" 1.3.1
  wait_for 120 "Freight with the image 1.3.1 was created" has_freight 1.3.1
  if ! stage_runs dev 1.3.1; then
    # the rollback put a hold on auto-promotion: promoting the current candidate lifts it
    kargo_cli promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    ok "promotion of 1.3.1 to dev started (it lifts the hold)"
    wait_for 240 "dev runs 1.3.1" stage_runs dev 1.3.1
  fi
  wait_for 240 "1.3.1 is verified in dev" freight_is_verified dev 1.3.1
}

kargo_login
for n in $(seq 1 "$TARGET"); do
  case "$n" in
    1) catchup_1 ;;
    2) catchup_2 ;;
    3) catchup_3 ;;
    4) catchup_4 ;;
    *) die "Lab $n is not written yet." ;;
  esac
done
printf '\n%sCaught up with lab %s.%s Run: make check STEP=%s\n' "$_C_GREEN" "$TARGET" "$_C_RESET" "$TARGET"
