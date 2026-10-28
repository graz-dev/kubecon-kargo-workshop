#!/usr/bin/env bash
# Checks that a step of the workshop did what it should. Read-only; prints one line per check and exits 1 when
# something is wrong, with a hint for each failure.
#
#   scripts/check.sh setup        the environment of phase 1: cluster, Gitea, the platform, the five apps, the Kargo project
#   scripts/check.sh 1            lab 1: the Warehouse, the Freight, the dev Stage, a successful promotion, Git and the app
#   scripts/check.sh 2            lab 2: the staging Stage, auto-promotion on dev, release 1.1.0 on dev, staging promoted by hand
#   scripts/check.sh 3            lab 3: the prod gate and the three regions, release 1.2.0 all the way to production
#   scripts/check.sh 4            lab 4: verification on dev and staging, the failed 1.3.0, the rollback, the hold and the fix 1.3.1
#   scripts/check.sh 5            lab 5: staging waits for a pull request in Gitea, 1.3.1 reaches staging when it is merged
#   scripts/check.sh 6            lab 6: the Warehouse follows the registry, the live release goes through every Stage
#   scripts/check.sh 7            lab 7: the inbox received a message for a promotion that succeeded and one that failed
#   scripts/check.sh 8            lab 8: dev rolled itself back to the stable Freight when the check of 1.3.0 failed
#   scripts/check.sh 9            lab 9: a freeze window on prod, and a promotion to prod that asked for a reason, an approval and an audit event
#   scripts/check.sh 10           lab 10: the Promotion Controller is on, and a promotion of dev ran two custom steps, a greeting and a scan
#
# The other labs add their own steps in later phases.
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
    creds="$(kargo_cli get repo-credentials --project "$KARGO_PROJECT" 2>/dev/null || true)"
    if grep -q "$(gitea_repo_url)" <<<"$creds"; then
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

# --- Labs ----------------------------------------------------------------------------------

# `TODO`s left in the attendee's own copy of a lab's files (work/lab-N/)
check_todos() { # <lab number>
  local dir="$ROOT_DIR/work/lab-$1" f hits
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.yaml; do
    [[ -f "$f" ]] || continue
    hits="$(grep -n -E '[:-][[:space:]]+TODO([[:space:]]|$)' "$f" | head -3 | tr '\n' ' ' || true)"
    [[ -z "$hits" ]] || bad "${f#"$ROOT_DIR"/} still has TODO to replace (line: $hits)" "replace it, then: kargo apply -f ${f#"$ROOT_DIR"/}"
  done
}

# True when `kargo get <what> -o json` mentions a version of our image
kargo_has() { # <kind> <pattern> [extra kargo args]
  local kind="$1" pattern="$2"
  shift 2
  local out
  out="$(kargo_cli get "$kind" --project "$KARGO_PROJECT" "$@" -o json 2>/dev/null || true)"
  grep -q -E "$pattern" <<<"$out"
}

# What the guestbook of a stage runs: prints the version shown on its page
stage_version() {
  curl -s -m 8 --resolve "$(service_host "guestbook-$1"):${HTTP_PORT}:127.0.0.1" "$(service_url "guestbook-$1")/" 2>/dev/null |
    sed -n 's/.*id="version">\([^<]*\)<.*/\1/p' | head -1
}

# The image tag a stage has in the GitOps repository (the "values.yaml" Kargo changes)
repo_tag() { gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/raw/env/$1/k8s/values.yaml" 2>/dev/null | sed -n 's/^ *tag: *//p' | head -1; }

check_lab1() {
  local tag
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  if kargo_cli get warehouses --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '$1=="app" {f=1} END {exit !f}'; then
    good "the Warehouse 'app' exists"
  else
    bad "there is no Warehouse 'app'" "run: kargo apply -f work/lab-1/warehouse.yaml (or make release VERSION=1.0.0)"
  fi
  if kargo_has freight '"tag": *"1\.0\.0"'; then
    good "Freight with the image 1.0.0 exists"
  else
    bad "no Freight with the image 1.0.0 yet" "wait a minute after: make release VERSION=1.0.0"
  fi
  if kargo_cli get stages --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '$1=="dev" {f=1} END {exit !f}'; then
    good "the Stage 'dev' exists"
  else
    bad "there is no Stage 'dev'" "apply yours: kargo apply -f work/lab-1/stage-dev.yaml"
  fi
  check_todos 1
  promotions="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage dev --no-headers 2>/dev/null || true)"
  if grep -q 'Succeeded' <<<"$promotions"; then
    good "a Promotion to 'dev' succeeded"
  else
    bad "no Promotion to 'dev' has succeeded" "promote the Freight: kargo promote --project $KARGO_PROJECT --freight-alias <alias> --stage dev; follow it with: kargo get promotions --project $KARGO_PROJECT --stage dev"
  fi

  section "Git and the applications"
  tag="$(repo_tag dev)"
  if [[ "$tag" == "1.0.0" ]]; then good "Git: env/dev/k8s/values.yaml has image tag 1.0.0"; else bad "Git: the dev values file has tag '${tag:-?}', not 1.0.0" "the promotion has not finished or has failed: look at its steps in Kargo"; fi
  commit="$(gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/commits?limit=1" 2>/dev/null | tr -d ' \n' || true)"
  if grep -q '"name":"kargo-bot"' <<<"$commit"; then
    good "Git: the latest commit was made by kargo-bot"
  else
    bad "Git: the latest commit was not made by kargo-bot" "a promotion makes it: check that git-commit and git-push ran"
  fi
  tag="$(stage_version dev)"
  if [[ "$tag" == "1.0.0" ]]; then good "dev runs 1.0.0 at $(service_url guestbook-dev)"; else bad "dev runs '${tag:-nothing}', not 1.0.0" "give Argo CD a minute, or check that the application guestbook-dev is Synced"; fi
  tag="$(stage_version staging)"
  if [[ "$tag" == "0.9.0" ]]; then good "staging still runs 0.9.0: nothing moved past dev"; else bad "staging runs '${tag:-nothing}'" "in this lab only dev should change"; fi
}

check_lab2() {
  local tag promotions
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  if kargo_cli get stages --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '$1=="staging" {f=1} END {exit !f}'; then
    good "the Stage 'staging' exists"
  else
    bad "there is no Stage 'staging'" "apply yours: kargo apply -f work/lab-2/stage-staging.yaml"
  fi
  if kargo_cli get projectconfig --project "$KARGO_PROJECT" -o yaml 2>/dev/null | tr -d ' ' | grep -q 'autoPromotionEnabled:true'; then
    good "the project promotes by itself: auto-promotion is on"
  else
    bad "no auto-promotion policy is on" "apply yours: kargo apply -f work/lab-2/project-config.yaml"
  fi
  check_todos 2
  if kargo_has freight '"tag": *"1\.1\.0"'; then
    good "Freight with the image 1.1.0 exists"
  else
    bad "no Freight with the image 1.1.0 yet" "run: make release VERSION=1.1.0 and wait a minute"
  fi
  promotions="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage dev --no-headers 2>/dev/null | grep -c 'Succeeded' || true)"
  if ((promotions >= 2)); then
    good "dev has had $promotions successful Promotions: the second one was made by Kargo"
  else
    bad "dev has had $promotions successful Promotion(s), and it should have two" "is auto-promotion on, and is 1.1.0 released? Look at: kargo get promotions --project $KARGO_PROJECT --stage dev"
  fi
  promotions="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage staging --no-headers 2>/dev/null | grep -c 'Succeeded' || true)"
  if ((promotions >= 1)); then
    good "a Promotion to 'staging' succeeded"
  else
    bad "no Promotion to 'staging' has succeeded" "promote by hand: kargo promote --project $KARGO_PROJECT --stage staging --warehouse app"
  fi

  section "Git and the applications"
  for stage in dev staging; do
    tag="$(repo_tag "$stage")"
    if [[ "$tag" == "1.1.0" ]]; then good "Git: env/$stage/k8s/values.yaml has image tag 1.1.0"; else bad "Git: the $stage values file has tag '${tag:-?}', not 1.1.0" "the promotion has not finished or has failed: look at its steps in Kargo"; fi
    tag="$(stage_version "$stage")"
    if [[ "$tag" == "1.1.0" ]]; then good "$stage runs 1.1.0 at $(service_url "guestbook-$stage")"; else bad "$stage runs '${tag:-nothing}', not 1.1.0" "give Argo CD a minute, or check that the application guestbook-$stage is Synced"; fi
  done
  tag="$(stage_version prod-amer-east)"
  if [[ "$tag" == "0.9.0" ]]; then good "production still runs 0.9.0: nothing moved past staging"; else bad "production runs '${tag:-nothing}'" "in this lab only dev and staging should change"; fi
}

check_lab3() {
  local tag promotions stage
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  for stage in prod prod-amer-east prod-amer-west prod-emea; do
    if kargo_cli get stages --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk -v s="$stage" '$1==s {f=1} END {exit !f}'; then
      good "the Stage '$stage' exists"
    else
      bad "there is no Stage '$stage'" "apply yours: kargo apply -f work/lab-3/stage-prod.yaml (prod) or work/lab-3/stage-prod-regions.yaml (the regions)"
    fi
  done
  if kargo_cli get projectconfig --project "$KARGO_PROJECT" -o yaml 2>/dev/null | tr -d ' "' | grep -q 'name:glob:prod-\*\|name:regex:prod-'; then
    good "the regions promote by themselves: there is an auto-promotion policy for them"
  else
    bad "no auto-promotion policy for the regions" "apply yours: kargo apply -f work/lab-3/project-config.yaml"
  fi
  check_todos 3
  if kargo_has freight '"tag": *"1\.2\.0"'; then
    good "Freight with the image 1.2.0 exists"
  else
    bad "no Freight with the image 1.2.0 yet" "run: make release VERSION=1.2.0 and wait a minute"
  fi
  for stage in prod prod-amer-east prod-amer-west prod-emea; do
    promotions="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage "$stage" --no-headers 2>/dev/null | grep -c 'Succeeded' || true)"
    if ((promotions >= 1)); then
      good "a Promotion to '$stage' succeeded"
    elif [[ "$stage" == prod ]]; then
      bad "no Promotion to 'prod' has succeeded" "promote by hand once staging runs 1.2.0: kargo promote --project $KARGO_PROJECT --stage prod --warehouse app"
    else
      bad "no Promotion to '$stage' has succeeded" "it follows prod by itself: is the policy applied, and did the Promotion to prod finish?"
    fi
  done

  section "Git and the applications"
  for stage in staging prod-amer-east prod-amer-west prod-emea; do
    tag="$(repo_tag "$stage")"
    if [[ "$tag" == "1.2.0" ]]; then good "Git: env/$stage/k8s/values.yaml has image tag 1.2.0"; else bad "Git: the $stage values file has tag '${tag:-?}', not 1.2.0" "the promotion has not finished or has failed: look at its steps in Kargo"; fi
    tag="$(stage_version "$stage")"
    if [[ "$tag" == "1.2.0" ]]; then good "$stage runs 1.2.0 at $(service_url "guestbook-$stage")"; else bad "$stage runs '${tag:-nothing}', not 1.2.0" "give Argo CD a minute, or check that the application guestbook-$stage is Synced"; fi
  done
}

check_lab4() {
  local tag stage_yaml
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  stage_yaml="$(kargo_cli get stage dev --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  if grep -q 'name: smoke-test' <<<"$stage_yaml"; then
    good "dev runs the smoke test after a promotion"
  else
    bad "dev has no verification" "apply yours: kargo apply -f work/lab-4/stage-dev.yaml"
  fi
  if kargo_cli get stage staging --project "$KARGO_PROJECT" -o yaml 2>/dev/null | grep -q 'name: e2e-test'; then
    good "staging runs the end-to-end test after a promotion"
  else
    bad "staging has no verification" "apply: kargo apply -f work/lab-4/stage-staging.yaml"
  fi
  check_todos 4
  if kargo_has freight '"tag": *"1\.3\.0"'; then
    good "Freight with the image 1.3.0 exists"
    if [[ -z "$(freight_verified_in dev 1.3.0)" ]]; then
      good "1.3.0 was never verified in dev: its check failed"
    else
      bad "1.3.0 is verified in dev" "its check should fail. Did you replace the TODO of the smoke test with the text Kargo Guestbook?"
    fi
  else
    bad "no Freight with the image 1.3.0" "run: make release VERSION=1.3.0"
  fi
  if grep -q 'phase: Failed' <<<"$stage_yaml"; then
    good "dev has a failed verification in its history"
  else
    bad "dev has no failed verification in its history" "release 1.3.0 and let dev take it: make release VERSION=1.3.0"
  fi
  if [[ -n "$(freight_verified_in dev 1.3.1)" ]]; then
    good "1.3.1 is verified in dev"
  else
    bad "1.3.1 is not verified in dev yet" "release it (make release VERSION=1.3.1), then resume: kargo promote --project $KARGO_PROJECT --stage dev --warehouse app"
  fi
  if grep -q 'autoPromotionHolds' <<<"$stage_yaml"; then
    bad "dev still has a hold on auto-promotion" "resume it by promoting the current candidate: kargo promote --project $KARGO_PROJECT --stage dev --warehouse app"
  else
    good "dev has no hold: auto-promotion is back"
  fi

  section "Git and the applications"
  tag="$(repo_tag dev)"
  if [[ "$tag" == "1.3.1" ]]; then good "Git: env/dev/k8s/values.yaml has image tag 1.3.1"; else bad "Git: the dev values file has tag '${tag:-?}', not 1.3.1" "the last promotion has not finished or has failed: look at its steps in Kargo"; fi
  tag="$(stage_version dev)"
  if [[ "$tag" == "1.3.1" ]]; then good "dev runs 1.3.1 at $(service_url guestbook-dev)"; else bad "dev runs '${tag:-nothing}', not 1.3.1" "give Argo CD a minute, or check that the application guestbook-dev is Synced"; fi
  for stage in staging prod-emea; do
    tag="$(repo_tag "$stage")"
    if [[ "$tag" == "1.2.0" ]]; then good "$stage still runs 1.2.0: the bad release never got past dev"; else bad "$stage has '${tag:-?}', not 1.2.0" "in this lab only dev should change"; fi
  done
}

check_lab5() {
  local tag stage_yaml pulls
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  stage_yaml="$(kargo_cli get stage staging --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  if grep -q 'git-open-pr' <<<"$stage_yaml" && grep -q 'git-wait-for-pr' <<<"$stage_yaml"; then
    good "staging opens a pull request and waits for it"
  else
    bad "staging has no pull request gate" "apply yours: kargo apply -f work/lab-5/stage-staging.yaml"
  fi
  check_todos 5
  if [[ -n "$(freight_verified_in staging 1.3.1)" ]]; then
    good "1.3.1 is verified in staging: the end-to-end test passed"
  else
    bad "1.3.1 is not verified in staging yet" "promote it (kargo promote --project $KARGO_PROJECT --stage staging --warehouse app) and merge the pull request in Gitea"
  fi

  section "Gitea"
  pulls="$(gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/pulls?state=all&limit=50" 2>/dev/null | tr -d ' \n' || true)"
  if grep -q '"merged":true' <<<"$pulls"; then
    good "a pull request was merged"
  else
    bad "no pull request has been merged" "open $(service_url gitea)/$GITEA_ORG/$GITEA_REPO/pulls, review the pull request of Kargo and merge it"
  fi
  if grep -q '"login":"kargo-bot"' <<<"$pulls"; then
    good "the pull request was opened by kargo-bot"
  else
    bad "no pull request from kargo-bot" "promote to staging after applying your Stage: kargo promote --project $KARGO_PROJECT --stage staging --warehouse app"
  fi
  if grep -q '"state":"open"' <<<"$pulls"; then
    bad "a pull request is still open" "review it and merge it, or close it: the Promotion is waiting for it"
  else
    good "no pull request is waiting"
  fi

  section "Git and the applications"
  tag="$(repo_tag staging)"
  if [[ "$tag" == "1.3.1" ]]; then good "Git: env/staging/k8s/values.yaml has image tag 1.3.1"; else bad "Git: the staging values file has tag '${tag:-?}', not 1.3.1" "the pull request is not merged yet, or the promotion failed: look at it in Kargo"; fi
  tag="$(stage_version staging)"
  if [[ "$tag" == "1.3.1" ]]; then good "staging runs 1.3.1 at $(service_url guestbook-staging)"; else bad "staging runs '${tag:-nothing}', not 1.3.1" "give Argo CD a minute, or check that the application guestbook-staging is Synced"; fi
  tag="$(repo_tag prod-emea)"
  if [[ "$tag" == "1.2.0" ]]; then good "production still runs 1.2.0: nothing moved past staging"; else bad "production has '${tag:-?}', not 1.2.0" "in this lab only staging should change"; fi
}

check_lab6() {
  local version stage pulls tag
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  if kargo_cli get warehouse app --project "$KARGO_PROJECT" -o yaml 2>/dev/null | grep -q 'imageSelectionStrategy: NewestBuild'; then
    good "the Warehouse follows the registry: it picks the image built most recently"
  else
    bad "the Warehouse does not use NewestBuild" "apply yours: kargo apply -f work/lab-6/warehouse.yaml"
  fi
  check_todos 6
  version="$(newest_freight_tag)"
  if [[ -n "$version" && "$version" != 1.3.1 && "$(printf '%s\n%s\n' 1.3.1 "$version" | sort -V | tail -1)" == "$version" ]]; then
    good "Kargo found a release newer than 1.3.1: $version"
  else
    bad "Kargo has found nothing newer than 1.3.1 yet" "wait for the instructor to publish the new version, then ask the Warehouse to look: kargo refresh warehouse app --project $KARGO_PROJECT"
    return 0
  fi
  for stage in dev staging prod prod-amer-east prod-amer-west prod-emea; do
    if [[ -n "$(freight_verified_in "$stage" "$version")" ]]; then
      good "$version went through $stage"
    else
      bad "$version has not been through $stage" "promote it, one Stage after the other: dev (by itself), staging (merge the pull request), prod, then the regions follow"
    fi
  done

  section "Gitea"
  pulls="$(gitea_api GET "/repos/$GITEA_ORG/$GITEA_REPO/pulls?state=all&limit=50" 2>/dev/null | tr -d ' \n' || true)"
  if grep -q "Promoteguestbook${version}tostaging" <<<"$pulls"; then
    good "Kargo opened a pull request for $version"
  else
    bad "no pull request for $version" "promote it to staging: kargo promote --project $KARGO_PROJECT --stage staging --warehouse app"
  fi
  if grep -q '"state":"open"' <<<"$pulls"; then
    bad "a pull request is still open" "review it and merge it: the Promotion is waiting for it"
  else
    good "no pull request is waiting"
  fi

  section "Git and the applications"
  for stage in dev staging prod-amer-east prod-amer-west prod-emea; do
    tag="$(repo_tag "$stage")"
    if [[ "$tag" == "$version" ]]; then good "Git: env/$stage/k8s/values.yaml has image tag $version"; else bad "Git: the $stage values file has tag '${tag:-?}', not $version" "the promotion has not finished or has failed: look at its steps in Kargo"; fi
    tag="$(stage_version "$stage")"
    if [[ "$tag" == "$version" ]]; then good "$stage runs $version at $(service_url "guestbook-$stage")"; else bad "$stage runs '${tag:-nothing}', not $version" "give Argo CD a minute, or check that the application guestbook-$stage is Synced"; fi
  done
}

check_lab7() {
  local id content
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  if kargo_cli get generic-credentials --project "$KARGO_PROJECT" --no-headers 2>/dev/null | awk '$1=="inbox-credentials" {f=1} END {exit !f}'; then
    good "the credentials of the channel exist"
  else
    bad "no credentials called inbox-credentials" "create them: kargo create generic-credentials --project $KARGO_PROJECT inbox-credentials --set bearerToken=workshop"
  fi
  check_todos 7

  section "The inbox"
  id="$(inbox_uuid)"
  if [[ -z "$id" ]]; then
    bad "I cannot find your inbox" "put its address in work/lab-7/message-channel.yaml (the line url:), then apply the file"
    return 0
  fi
  good "your inbox is https://webhook.site/#!/view/$id"
  content="$(inbox_content "$id")"
  if grep -q 'PromotionSucceeded' <<<"$content"; then
    good "the inbox received a message for a promotion that succeeded"
  else
    bad "nothing about a successful promotion in the inbox" "apply the channel and the router, then promote: kargo promote --project $KARGO_PROJECT --stage dev --warehouse app"
  fi
  if grep -q 'PromotionFailed' <<<"$content"; then
    good "the inbox received a message for a promotion that failed"
  else
    bad "nothing about a failed promotion in the inbox" "promote an older version to staging and close its pull request in Gitea without merging it"
  fi
}

check_lab8() {
  local version stage_yaml tag
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  if kargo_cli get projectconfig --project "$KARGO_PROJECT" -o yaml 2>/dev/null | grep -q 'autoRollback'; then
    good "the project has an automatic rollback policy"
  else
    bad "no automatic rollback policy" "apply yours: kargo apply -f work/lab-8/project-config.yaml"
  fi
  check_todos 8
  if kargo_has freight '"tag": *"1\.3\.0"' && [[ -z "$(freight_verified_in dev 1.3.0)" ]]; then
    good "1.3.0 was never verified in dev: its check failed"
  else
    bad "1.3.0 is verified in dev, or does not exist" "promote the broken version to dev: kargo promote --project $KARGO_PROJECT --freight-alias <alias of 1.3.0> --stage dev"
  fi
  if kargo_cli get promotions --project "$KARGO_PROJECT" --stage dev -o yaml 2>/dev/null | grep -q 'kargo.akuity.io/rollback: "true"'; then
    good "dev has a rollback Promotion that Kargo made by itself"
  else
    bad "no rollback Promotion on dev" "promote 1.3.0 to dev with the policy applied, and wait a minute"
  fi
  stage_yaml="$(kargo_cli get stage dev --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  if grep -q 'autoPromotionHolds' <<<"$stage_yaml"; then
    bad "dev still has a hold on auto-promotion" "resume it by promoting the current candidate: kargo promote --project $KARGO_PROJECT --stage dev --warehouse app"
  else
    good "dev has no hold: auto-promotion is back"
  fi

  section "Git and the applications"
  version="$(newest_freight_tag)"
  tag="$(repo_tag dev)"
  if [[ -n "$version" && "$tag" == "$version" ]]; then good "Git: env/dev/k8s/values.yaml has image tag $version, the newest"; else bad "Git: the dev values file has tag '${tag:-?}', not the newest ($version)" "the rollback has not finished: look at the Promotions of dev"; fi
  tag="$(stage_version dev)"
  if [[ -n "$version" && "$tag" == "$version" ]]; then good "dev runs $version at $(service_url guestbook-dev)"; else bad "dev runs '${tag:-nothing}', not $version" "give Argo CD a minute, or check that the application guestbook-dev is Synced"; fi
}

check_lab9() {
  local config stage_yaml promotions
  section "Kargo"
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  config="$(kargo_cli get projectconfig --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  if grep -q 'name: workshop-freeze' <<<"$config" && grep -q 'kind: Deny' <<<"$config"; then
    good "the project has a freeze window on prod"
  else
    bad "no Deny window called workshop-freeze" "apply yours: kargo apply -f work/lab-9/project-config.yaml"
  fi
  if grep -q 'disabled: true' <<<"$config"; then
    good "the freeze is lifted: prod accepts promotions"
  else
    bad "the freeze is still on" "set disabled to true in work/lab-9/project-config.yaml and apply it again"
  fi
  stage_yaml="$(kargo_cli get stage prod --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  if grep -q 'get-user-input' <<<"$stage_yaml" && grep -q 'wait-for-approval' <<<"$stage_yaml" && grep -q 'record-audit-event' <<<"$stage_yaml"; then
    good "prod asks for a reason, waits for an approval and records an audit event"
  else
    bad "prod is missing one of the three steps" "apply yours: kargo apply -f work/lab-9/stage-prod.yaml"
  fi
  check_todos 9
  promotions="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage prod -o yaml 2>/dev/null || true)"
  if grep -q 'action: approve' <<<"$promotions"; then
    good "a promotion to prod was approved"
  else
    bad "no promotion to prod has been approved" "promote, then answer the form and approve in the Kargo UI: kargo promote --project $KARGO_PROJECT --stage prod --warehouse app"
  fi
  if grep -q 'recorded audit event "approved"' <<<"$promotions"; then
    good "the approval was recorded in the audit log"
  else
    bad "no audit event was recorded" "it is written by the last step of the promotion: look at the steps of the promotion in Kargo"
  fi
}

check_lab10() {
  local stage_yaml promotions
  section "Kargo"
  if kubectl -n akuity get deploy "kargo-promotion-controller-$CLUSTER_NAME" >/dev/null 2>&1; then
    good "the Promotion Controller is on"
  else
    bad "the Promotion Controller is off" "turn it on: make promotion-controller STATE=on"
  fi
  if ! kargo_login 2>/dev/null; then
    bad "could not log in to Kargo with the admin account" "run: make urls, and log in again with the kargo login line it prints"
    return 0
  fi
  stage_yaml="$(kargo_cli get stage dev --project "$KARGO_PROJECT" -o yaml 2>/dev/null || true)"
  if grep -q 'uses: hello-world' <<<"$stage_yaml" && grep -q 'uses: trivy-image' <<<"$stage_yaml"; then
    good "dev uses the two custom steps"
  else
    bad "dev does not use hello-world and trivy-image" "apply yours: kargo apply -f work/lab-10/stage-dev.yaml"
  fi
  check_todos 10
  promotions="$(kargo_cli get promotions --project "$KARGO_PROJECT" --stage dev -o yaml 2>/dev/null || true)"
  if grep -q 'message: Hello from the dev promotion!' <<<"$promotions"; then
    good "a promotion of dev ran hello-world"
  else
    bad "no promotion of dev has run hello-world" "register the steps and apply the Stage, then promote: kargo promote --project $KARGO_PROJECT --stage dev --warehouse app"
  fi
  if grep -q 'Report Summary' <<<"$promotions"; then
    good "a promotion of dev ran the Trivy scan and kept its report"
  else
    bad "no scan report in the promotions of dev" "the scan takes about a minute: wait for the Promotion to finish"
  fi
}

case "$STEP" in
  1) check_lab1 ;;
  2) check_lab2 ;;
  3) check_lab3 ;;
  4) check_lab4 ;;
  5) check_lab5 ;;
  6) check_lab6 ;;
  7) check_lab7 ;;
  8) check_lab8 ;;
  9) check_lab9 ;;
  10) check_lab10 ;;
  setup) check_setup ;;
  "") die "Say which step: make check STEP=setup" ;;
  *) die "Unknown step '$STEP'. Known now: setup, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10." ;;
esac

printf '\n'
if ((FAILS > 0)); then
  printf '%s%d check(s) failed.%s Follow the hints above and run the check again.\n' "$_C_RED" "$FAILS" "$_C_RESET"
  exit 1
fi
printf '%sAll good.%s\n' "$_C_GREEN" "$_C_RESET"
