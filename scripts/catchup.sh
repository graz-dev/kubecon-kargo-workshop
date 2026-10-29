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
stage_ready() { # <stage>: true when the Stage reports Ready
  local out
  out="$(kargo_cli get stages --project "$KARGO_PROJECT" --no-headers 2>/dev/null || true)"
  grep -q -E "^$1 .* True " <<<"$out"
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

# kargo promote, for a Stage that was applied a moment ago: the platform needs a few seconds to see it, and until then it answers
# "could not find Stage". Tries for about a minute; any other error stops at once.
kargo_promote() {
  local try out
  for try in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if out="$(kargo_cli promote "$@" 2>&1)"; then
      printf '%s\n' "$out"
      return 0
    fi
    case "$out" in
      *"could not find"* | *"Not found"* | *"not found"*) sleep 5 ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$out" >&2
  return 1
}

# Like apply_step_file, for a file that points to something applied a moment ago (an event router and its channel): the platform
# needs a few seconds to see the new resource, and until then it answers "not found". Tries for about a minute.
apply_step_file_waiting() { # <N> <file>
  local try
  for try in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if apply_step_file "$1" "$2" 2>"$WORK/apply.err"; then
      return 0
    fi
    grep -q 'Not found' "$WORK/apply.err" || break
    sleep 5
  done
  cat "$WORK/apply.err" >&2
  die "Could not apply steps/$1/$2"
}

catchup_1() {
  step "Lab 1: the first release, the dev Stage, the first promotion"
  "$LIB_DIR/../release.sh" 1.0.0
  wait_for 120 "Freight with the image 1.0.0 was created" has_freight 1.0.0
  apply_step_file 1 stage-dev.yaml
  if [[ "$(repo_tag dev)" == "1.0.0" ]] && promotion_succeeded dev; then
    ok "dev already has 1.0.0: nothing to promote"
  else
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
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
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev 1.1.0)" --stage staging >/dev/null
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
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev 1.2.0)" --stage staging >/dev/null
    ok "promotion to staging started"
  fi
  wait_for 240 "staging runs 1.2.0" stage_runs staging 1.2.0
  if [[ "$(repo_tag prod-emea)" == "1.2.0" ]]; then
    ok "production already has 1.2.0: nothing to promote"
  else
    wait_for 120 "Freight 1.2.0 is verified in staging" freight_is_verified staging 1.2.0
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in staging 1.2.0)" --stage prod >/dev/null
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
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev 1.2.0)" --stage dev >/dev/null
    ok "rollback of dev to 1.2.0 started"
    wait_for 240 "dev runs 1.2.0 again" stage_runs dev 1.2.0
  fi
  "$LIB_DIR/../release.sh" 1.3.1
  wait_for 120 "Freight with the image 1.3.1 was created" has_freight 1.3.1
  if ! stage_runs dev 1.3.1; then
    # the rollback put a hold on auto-promotion: promoting the current candidate lifts it
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    ok "promotion of 1.3.1 to dev started (it lifts the hold)"
    wait_for 240 "dev runs 1.3.1" stage_runs dev 1.3.1
  fi
  wait_for 240 "1.3.1 is verified in dev" freight_is_verified dev 1.3.1
}

# The number of the first open pull request of the GitOps repository (empty when there is none)
open_pull_request() {
  gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/pulls?state=open" 2>/dev/null | sed -n 's/.*"number": *\([0-9][0-9]*\).*/\1/p' | head -1 || true
}
has_open_pull_request() { [[ -n "$(open_pull_request)" ]]; }

# Promotes a version to staging, merges the pull request Kargo opens (the attendee does it in the Gitea page, here it is the
# API with the same user) and waits for the end-to-end test
staging_through_pr() { # <version>
  local version="$1" number
  if [[ "$(repo_tag staging)" == "$version" ]]; then
    ok "staging already has $version: nothing to promote"
  else
    if ! has_open_pull_request; then
      kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in dev "$version")" --stage staging >/dev/null
      ok "promotion to staging started"
      wait_for 120 "Kargo opened a pull request in Gitea" has_open_pull_request
    fi
    number="$(open_pull_request)"
    gitea_curl -u "$GITEA_USER:$GITEA_PASSWORD" -H 'Content-Type: application/json' -X POST -o /dev/null \
      -d '{"Do":"merge"}' "$(gitea_url)/api/v1/repos/$GITEA_ORG/$GITEA_REPO/pulls/$number/merge"
    ok "pull request $number merged"
  fi
  wait_for 240 "staging runs $version" stage_runs staging "$version"
  wait_for 240 "$version is verified in staging" freight_is_verified staging "$version"
}

catchup_5() {
  step "Lab 5: staging waits for a pull request, which is merged"
  apply_step_file 5 stage-staging.yaml
  staging_through_pr 1.3.1
}

# Asks the Warehouse to look at the registry now, then says whether the version has become Freight
refresh_and_has_freight() {
  kargo_cli refresh warehouse --project "$KARGO_PROJECT" app >/dev/null 2>&1 || true
  has_freight "$1"
}

catchup_6() {
  step "Lab 6: the Warehouse follows the registry, the live release goes all the way to production"
  local version="${LIVE_VERSION:-${LIVE_VERSIONS%% *}}" cfg region
  [[ -n "$version" ]] || die "No live version is set (LIVE_VERSIONS in workshop.env)."
  cfg="$(mktemp -d)"
  if ! DOCKER_CONFIG="$cfg" "$TOOLS_BIN/crane" manifest "$(image_repo_cluster):$version" >/dev/null 2>&1; then
    rm -rf "$cfg"
    die "Version $version is not on the registry yet. The instructor publishes it during the lab: wait for the signal, then run this again."
  fi
  rm -rf "$cfg"
  apply_step_file 6 warehouse.yaml
  wait_for 240 "Freight with the image $version was created" refresh_and_has_freight "$version"
  wait_for 300 "dev runs $version (promoted by Kargo)" stage_runs dev "$version"
  wait_for 240 "$version is verified in dev" freight_is_verified dev "$version"
  staging_through_pr "$version"
  if [[ "$(repo_tag prod-emea)" == "$version" ]]; then
    ok "production already has $version: nothing to promote"
  else
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in staging "$version")" --stage prod >/dev/null
    ok "promotion to prod started"
  fi
  for region in prod-amer-east prod-amer-west prod-emea; do
    wait_for 300 "$region runs $version" stage_runs "$region" "$version"
  done
}

# True when the inbox has received something that matches
inbox_has() { # <id> <text>
  grep -q "$2" <<<"$(inbox_content "$1")"
}

catchup_7() {
  step "Lab 7: an inbox, a channel, a router, one promotion that succeeds and one that fails"
  local id number
  id="$(inbox_uuid)"
  if [[ -z "$id" ]]; then
    id="$(inbox_create)"
    [[ -n "$id" ]] || die "Could not create an inbox at webhook.site. Check your connection and try again."
    mkdir -p "$TOOLS_DIR"
    printf '%s' "$id" >"$INBOX_FILE"
  fi
  export INBOX_URL="https://webhook.site/$id"
  ok "your inbox: https://webhook.site/#!/view/$id"
  if ! kargo_cli get generic-credentials --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '$1=="inbox-credentials" {f=1} END {exit !f}'; then
    kargo_cli create generic-credentials --project "$KARGO_PROJECT" inbox-credentials --set bearerToken=workshop >/dev/null
    ok "credentials inbox-credentials created"
  fi
  apply_step_file 7 message-channel.yaml
  apply_step_file_waiting 7 event-router.yaml
  if inbox_has "$id" PromotionSucceeded; then
    ok "the inbox already has a message for a promotion that succeeded"
  else
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    wait_for 120 "the inbox received PromotionSucceeded" inbox_has "$id" PromotionSucceeded
  fi
  if inbox_has "$id" PromotionFailed; then
    ok "the inbox already has a message for a promotion that failed"
  else
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_verified_in staging 1.3.1)" --stage staging >/dev/null
    wait_for 120 "Kargo opened a pull request in Gitea" has_open_pull_request
    number="$(open_pull_request)"
    gitea_api PATCH "/repos/$GITEA_ORG/$GITEA_REPO/pulls/$number" -o /dev/null -d '{"state":"closed"}'
    ok "pull request $number closed without merging"
    wait_for 120 "the inbox received PromotionFailed" inbox_has "$id" PromotionFailed
    # a failed promotion leaves staging with an error until the next one: promote what it already has
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage staging >/dev/null
    wait_for 120 "staging is ready again" stage_ready staging
  fi
}

# The name of the Freight with this image tag (empty when there is none)
freight_named() { # <tag>
  kargo_cli get freight --project "$KARGO_PROJECT" -o jsonpath='{range .items[*]}{.metadata.name} {.images[0].tag}{"\n"}{end}' 2>/dev/null |
    awk -v tag="$1" '$2 == tag {print $1; exit}' || true
}

has_rollback_promotion() {
  local out
  out="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage dev -o yaml 2>/dev/null || true)"
  grep -q 'kargo.akuity.io/rollback: "true"' <<<"$out"
}

dev_has_no_hold() {
  local out
  out="$(kargo_cli get stage dev --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  ! grep -q 'autoPromotionHolds' <<<"$out"
}

catchup_8() {
  step "Lab 8: dev rolls itself back when the check of 1.3.0 fails"
  local version
  version="$(newest_freight_tag)"
  [[ -n "$version" ]] || die "There is no Freight yet."
  apply_step_file 8 project-config.yaml
  if has_rollback_promotion; then
    ok "dev has already rolled itself back once"
  else
    kargo_promote --project "$KARGO_PROJECT" --freight "$(freight_named 1.3.0)" --stage dev >/dev/null
    ok "1.3.0 promoted to dev"
    wait_for 240 "Kargo rolled dev back by itself" has_rollback_promotion
  fi
  wait_for 240 "dev runs $version again" stage_runs dev "$version"
  if ! dev_has_no_hold; then
    # the rollback put a hold on auto-promotion: promoting the current candidate lifts it
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    wait_for 120 "the hold on dev is gone" dev_has_no_hold
  fi
  wait_for 240 "$version is verified in dev" freight_is_verified dev "$version"
}

# The newest promotion of a Stage (its name)
newest_promotion() { # <stage>
  kargo_cli get promotions --project "$KARGO_PROJECT" --stage "$1" --no-headers 2>/dev/null | tail -1 | cut -d' ' -f1 || true
}

# True when a step of a promotion is waiting for a person
promotion_step_waiting() { # <promotion> <step alias>
  kargo_cli get promotion "$1" --project "$KARGO_PROJECT" -o yaml 2>/dev/null |
    awk -v a="$2" '/- alias:/ {cur = $3} cur == a && /status: Running/ {f = 1} END {exit !f}'
}

promotion_finished() { # <promotion>
  local out
  out="$(kargo_cli get promotions --project "$KARGO_PROJECT" --no-headers 2>/dev/null || true)"
  grep -q -E "^$1 .* (Succeeded|Failed|Errored|Aborted) " <<<"$out"
}

prod_was_approved() {
  local out
  out="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage prod -o yaml 2>/dev/null || true)"
  grep -q 'recorded audit event "approved"' <<<"$out"
}

catchup_9() {
  step "Lab 9: a freeze window (lifted), and a promotion to prod that asks for a reason, an approval and an audit event"
  local name
  apply_step_file 9 project-config.yaml
  apply_step_file 9 stage-prod.yaml
  if prod_was_approved; then
    ok "a promotion to prod was already approved and recorded"
  else
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage prod >/dev/null
    name="$(newest_promotion prod)"
    ok "promotion $name started"
    # the attendee answers in the Kargo UI: here it is the call the UI makes, with the same user
    wait_for 120 "the promotion asks for a reason" promotion_step_waiting "$name" reason
    kargo_api POST "/enterprise/v1beta1/projects/$KARGO_PROJECT/promotions/$name/steps/reason/respond" \
      '{"action":"submit","values":{"reason":"Catch-up: approved by the workshop script"}}' >/dev/null
    wait_for 120 "the promotion waits for the approval" promotion_step_waiting "$name" approve
    kargo_api POST "/enterprise/v1beta1/projects/$KARGO_PROJECT/promotions/$name/steps/approve/respond" '{"action":"approve"}' >/dev/null
    wait_for 180 "the promotion to prod finished" promotion_finished "$name"
    wait_for 60 "the approval was recorded" prod_was_approved
  fi
}

dev_ran_custom_steps() {
  local out
  out="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage dev -o yaml 2>/dev/null || true)"
  grep -q 'Report Summary' <<<"$out"
}

catchup_10() {
  step "Lab 10: the Promotion Controller, two custom steps, a promotion of dev that scans the image"
  local name
  # shellcheck source=lib/seed.sh
  source "$LIB_DIR/seed.sh"
  DRY_RUN=0
  platform_preflight
  set_promotion_controller on
  apply_step_file 10 custom-steps.yaml
  apply_step_file 10 stage-dev.yaml
  if dev_ran_custom_steps; then
    ok "dev has already run the custom steps"
  else
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    name="$(newest_promotion dev)"
    ok "promotion $name started (the scan takes about a minute)"
    wait_for 300 "the promotion of dev finished" promotion_finished "$name"
    wait_for 60 "the report of the scan is kept" dev_ran_custom_steps
  fi
}

dev_has_lambda_url() {
  gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/raw/env/dev/k8s/values.yaml" 2>/dev/null | grep -q 'LAMBDA_URL: *"\{0,1\}https://'
}

catchup_11() {
  step "Lab 11: dev applies the Terraform that makes a Lambda and gives its URL to the application"
  local name
  # the Secret holds the key of the instructor: a script cannot invent it
  if ! kargo_cli get generic-credentials --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '$1=="aws-creds" {f=1} END {exit !f}'; then
    die "There is no Secret called aws-creds. Create it first with the key and the secret that the instructor gave you (step 1 of Lab 11), then run this again."
  fi
  # the Lambda and the Terraform are in the repository (make seed adds them)
  "$LIB_DIR/../lab11-files.sh"
  apply_step_file 11 stage-dev.yaml
  if dev_has_lambda_url && promotion_succeeded dev && [[ "${FORCE:-0}" != 1 ]]; then
    ok "dev already has the URL of its Lambda: nothing to promote"
  else
    # same id, same state file: when the Lambda exists the Terraform finds it and changes nothing
    kargo_promote --project "$KARGO_PROJECT" --warehouse app --stage dev >/dev/null
    name="$(newest_promotion dev)"
    ok "promotion $name started (about a minute and a half)"
    wait_for 360 "the promotion of dev finished" promotion_finished "$name"
    wait_for 60 "the URL of the Lambda is in Git" dev_has_lambda_url
  fi
}

kargo_login
for n in $(seq 1 "$TARGET"); do
  case "$n" in
    1) catchup_1 ;;
    2) catchup_2 ;;
    3) catchup_3 ;;
    4) catchup_4 ;;
    5) catchup_5 ;;
    6) catchup_6 ;;
    7) catchup_7 ;;
    8) catchup_8 ;;
    9) catchup_9 ;;
    10) catchup_10 ;;
    11) catchup_11 ;;
    *) die "Lab $n is not written yet." ;;
  esac
done
printf '\n%sCaught up with lab %s.%s Run: make check STEP=%s\n' "$_C_GREEN" "$TARGET" "$_C_RESET" "$TARGET"
