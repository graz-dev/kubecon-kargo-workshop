#!/usr/bin/env bash
# Installs Gitea in the kind cluster and creates what the labs start from. Local only (no Akuity Platform).
# Idempotent: running it again changes nothing that already exists.
#   1. Gitea (Helm, SQLite) at http://gitea.${WORKSHOP_DOMAIN}[:port]
#   2. the organization, the repository, the users (workshop = the attendee, kargo-bot = what Kargo pushes as)
#   3. an access token for kargo-bot, kept in .tools/gitea.env
#   4. the initial content of the repository: the guestbook chart and one values file per stage (at INITIAL_VERSION)
#
#   scripts/gitea-up.sh [--recreate-repo]     --recreate-repo deletes the repository and creates it again from scratch
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools

RECREATE=0
for arg in "$@"; do
  case "$arg" in
    --recreate-repo) RECREATE=1 ;;
    -h | --help)
      sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument '$arg'" ;;
  esac
done
cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
step() { printf '\n%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }
SAFE='^[A-Za-z0-9._@%+=:,/!#-]+$' # what we allow in the passwords we put into JSON and URLs
for pw in "$GITEA_ADMIN_PASSWORD" "$GITEA_PASSWORD"; do
  [[ "$pw" =~ $SAFE ]] || die "A Gitea password in workshop.env has characters outside letters, digits and . _ @ % + = : , / ! # -"
done

# Payloads are built in plain variables with single quotes, never with \" inside "$( )": bash 3.2 (macOS) splits those
# on the commas and the braces.
json() { # json key value [key value ...]: a flat JSON object; a value starting with = is raw (true, false, a number)
  local out="{" sep="" k v
  while (($# >= 2)); do
    k="$1" v="$2"
    shift 2
    case "$v" in
      =*) out="$out$sep\"$k\":${v#=}" ;;
      *) out="$out$sep\"$k\":\"$v\"" ;;
    esac
    sep=","
  done
  printf '%s}' "$out"
}

expect() { # <label> <actual> <expected...>: ok when the status is one of the expected ones
  local label="$1" got="$2" want
  shift 2
  for want in "$@"; do [[ "$got" == "$want" ]] && return 0; done
  die "$label: Gitea answered HTTP $got (expected $*)"
}

# --- 1. Gitea ------------------------------------------------------------------------------
step "Gitea $GITEA_CHART_VERSION"
export GITEA_HOST GITEA_URL
GITEA_HOST="$(service_host gitea)"
GITEA_URL="$(gitea_url)"
render_template "$ROOT_DIR/manifests/gitea-values.yaml" >"$WORK/gitea-values.yaml"
helm upgrade --install gitea gitea \
  --repo "$GITEA_CHART_REPO" --version "$GITEA_CHART_VERSION" \
  --namespace gitea --create-namespace --values "$WORK/gitea-values.yaml" --wait --timeout 8m >/dev/null
ok "gitea deployed"
for _ in $(seq 1 60); do
  [[ "$(gitea_curl -o /dev/null -w '%{http_code}' "$GITEA_URL/api/v1/version" 2>/dev/null || true)" == 200 ]] && break
  sleep 3
done
[[ "$(gitea_code GET /user 2>/dev/null || true)" == 200 ]] ||
  die "Gitea does not answer at $GITEA_URL (or the administrator '$GITEA_ADMIN_USER' cannot log in). Check: kubectl -n gitea get pods"
ok "gitea answers at $GITEA_URL as $GITEA_ADMIN_USER"

# --- 2. Organization, users, repository ----------------------------------------------------
step "Organization '$GITEA_ORG', users and repository '$GITEA_REPO'"
if [[ "$(gitea_code GET "/orgs/$GITEA_ORG")" == 404 ]]; then
  body="$(json username "$GITEA_ORG" visibility public)"
  code="$(gitea_code POST /orgs -d "$body")"
  expect "creating the organization" "$code" 201
  ok "organization $GITEA_ORG created"
else
  ok "organization $GITEA_ORG exists"
fi

# kargo-bot has its own random password (only needed to mint tokens), kept next to the token
BOT=kargo-bot
GITEA_BOT_PASSWORD="" GITEA_BOT_TOKEN=""
if [[ -f "$GITEA_ENV" ]]; then
  GITEA_BOT_PASSWORD="$(sed -n 's/^GITEA_BOT_PASSWORD=//p' "$GITEA_ENV")"
  GITEA_BOT_TOKEN="$(sed -n 's/^GITEA_BOT_TOKEN=//p' "$GITEA_ENV")"
fi
[[ -n "$GITEA_BOT_PASSWORD" ]] || GITEA_BOT_PASSWORD="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"

ensure_user() { # <name> <password> <email>
  local name="$1" pw="$2" email="$3" body code
  if [[ "$(gitea_code GET "/users/$name")" == 404 ]]; then
    body="$(json username "$name" email "$email" password "$pw" must_change_password =false visibility public)"
    code="$(gitea_code POST /admin/users -d "$body")"
    expect "creating user $name" "$code" 201
    ok "user $name created"
  else
    # keeps the password equal to workshop.env if it was changed
    body="$(json login_name "$name" source_id =0 email "$email" password "$pw")"
    code="$(gitea_code PATCH "/admin/users/$name" -d "$body")"
    expect "updating user $name" "$code" 200
    ok "user $name exists"
  fi
}
ensure_user "$GITEA_USER" "$GITEA_PASSWORD" "$GITEA_USER@workshop.local"
ensure_user "$BOT" "$GITEA_BOT_PASSWORD" "$BOT@workshop.local"

create_repo() {
  local body code
  body="$(json name "$GITEA_REPO" default_branch "$GITEA_BRANCH" private =false description 'GitOps repository of the Kargo workshop')"
  code="$(gitea_code POST "/orgs/$GITEA_ORG/repos" -d "$body")"
  expect "creating the repository" "$code" 201
}
if [[ "$RECREATE" == 1 && "$(gitea_code GET "/repos/$GITEA_ORG/$GITEA_REPO")" == 200 ]]; then
  code="$(gitea_code DELETE "/repos/$GITEA_ORG/$GITEA_REPO")"; expect "deleting the repository" "$code" 204
  ok "repository deleted"
fi
if [[ "$(gitea_code GET "/repos/$GITEA_ORG/$GITEA_REPO")" == 404 ]]; then
  create_repo
  ok "repository $GITEA_ORG/$GITEA_REPO created"
else
  ok "repository $GITEA_ORG/$GITEA_REPO exists"
fi
# Permissions of an organization repository come from teams: one team with write access to every repository
TEAM=writers
team_id() { gitea_api GET "/orgs/$GITEA_ORG/teams" | tr '{' '\n' | grep "\"name\":\"$TEAM\"" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1; }
if [[ -z "$(team_id)" ]]; then
  body='{"name":"'$TEAM'","description":"Can read, write and merge","includes_all_repositories":true,"permission":"write","units":["repo.code","repo.issues","repo.pulls"]}'
  code="$(gitea_code POST "/orgs/$GITEA_ORG/teams" -d "$body")"
  expect "creating the team" "$code" 201
fi
TEAM_ID="$(team_id)"
[[ -n "$TEAM_ID" ]] || die "Could not find the team '$TEAM' in the organization $GITEA_ORG"
for u in "$GITEA_USER" "$BOT"; do
  code="$(gitea_code PUT "/teams/$TEAM_ID/members/$u")"
  expect "adding $u to the team" "$code" 204
done
ok "$GITEA_USER and $BOT can read, write and merge in every repository of $GITEA_ORG"

# --- 3. Token of kargo-bot -----------------------------------------------------------------
step "Access token of $BOT"
token_works() {
  [[ -n "$GITEA_BOT_TOKEN" ]] &&
    [[ "$(gitea_curl -o /dev/null -w '%{http_code}' -H "Authorization: token $GITEA_BOT_TOKEN" "$GITEA_URL/api/v1/user")" == 200 ]]
}
if token_works; then
  ok "the saved token still works"
else
  # an old token with the same name would block the new one; its value cannot be read back, so replace it
  gitea_curl -o /dev/null -u "$BOT:$GITEA_BOT_PASSWORD" -X DELETE "$GITEA_URL/api/v1/users/$BOT/tokens/kargo" || true
  body="$(gitea_curl -u "$BOT:$GITEA_BOT_PASSWORD" -H 'Content-Type: application/json' -X POST "$GITEA_URL/api/v1/users/$BOT/tokens" \
    -d '{"name":"kargo","scopes":["write:repository","write:issue","read:user"]}')"
  GITEA_BOT_TOKEN="$(printf '%s' "$body" | sed -n 's/.*"sha1":"\([^"]*\)".*/\1/p')"
  [[ -n "$GITEA_BOT_TOKEN" ]] || die "Could not create the token of $BOT: $body"
  ok "token created"
fi
mkdir -p "$TOOLS_DIR"
(umask 077 && printf 'GITEA_BOT_PASSWORD=%s\nGITEA_BOT_TOKEN=%s\n' "$GITEA_BOT_PASSWORD" "$GITEA_BOT_TOKEN" >"$GITEA_ENV")

# --- 4. Initial content --------------------------------------------------------------------
step "Initial content of the repository (every stage at $INITIAL_VERSION)"
# (asked of git itself: the API's "empty" flag lags a little behind a push)
REMOTE="http://$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD@127.0.0.1:$HTTP_PORT/$GITEA_ORG/$GITEA_REPO.git"
if ! git -c "http.extraHeader=Host: $GITEA_HOST$(port_suffix)" ls-remote --heads "$REMOTE" "$GITEA_BRANCH" 2>/dev/null | grep -q "refs/heads/$GITEA_BRANCH"; then
  export CLUSTER_IMAGE_REPO STAGE STAGE_HOST
  CLUSTER_IMAGE_REPO="$(image_repo_cluster)"
  tree="$WORK/repo"
  mkdir -p "$tree"
  cp -R "$ROOT_DIR/seed/charts" "$tree/charts"
  cp "$ROOT_DIR/seed/README.md" "$tree/README.md"
  render_template "$ROOT_DIR/seed/charts/guestbook/values.yaml" >"$tree/charts/guestbook/values.yaml"
  for STAGE in $STAGES; do
    STAGE_HOST="$(service_host "guestbook-$STAGE")"
    mkdir -p "$tree/env/$STAGE/k8s"
    render_template "$ROOT_DIR/seed/env-values.yaml" >"$tree/env/$STAGE/k8s/values.yaml"
  done
  git -C "$tree" init -q -b "$GITEA_BRANCH"
  git -C "$tree" add -A
  git -C "$tree" -c user.name="Kargo workshop" -c user.email="workshop@workshop.local" commit -q -m "Initial state of the workshop"
  # pushed to the local port with the Host header Traefik routes on, so it does not depend on public DNS
  git -C "$tree" -c "http.extraHeader=Host: $GITEA_HOST$(port_suffix)" \
    push -q "$REMOTE" "$GITEA_BRANCH"
  ok "initial content pushed"
else
  ok "the repository already has content (use 'make reset' to start over)"
fi

printf '\n%sGitea is ready.%s\n' "$_C_GREEN" "$_C_RESET"
printf '  %s   attendee: %s / %s\n  repository: %s\n' "$GITEA_URL" "$GITEA_USER" "$GITEA_PASSWORD" "$(gitea_repo_url)"
