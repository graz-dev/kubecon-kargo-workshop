#!/usr/bin/env bash
# Shared helpers for the workshop scripts. Source this file; do not execute it.
# Must run on bash 3.2 (macOS default): no associative arrays, mapfile or ${var,,}.

if [[ -n "${_WORKSHOP_LIB_LOADED:-}" ]]; then
  return 0
fi
_WORKSHOP_LIB_LOADED=1

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$LIB_DIR/../.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools"
TOOLS_BIN="$TOOLS_DIR/bin"

# Our scripts use their own kubeconfig and Helm state, so they never touch (or depend on) the user's
# ~/.kube/config, current context or Helm repositories.
export KUBECONFIG="$TOOLS_DIR/kubeconfig"
export HELM_CACHE_HOME="$TOOLS_DIR/helm/cache"
export HELM_CONFIG_HOME="$TOOLS_DIR/helm/config"
export HELM_DATA_HOME="$TOOLS_DIR/helm/data"

# NodePort of the Traefik Service: the single port that kind publishes on the host (fixed by design)
export TRAEFIK_NODE_PORT=30080
export TRAEFIK_NAMESPACE=traefik

# Stages of the guestbook pipeline (fixed by the workshop design, not configurable)
# shellcheck disable=SC2034 # used by the scripts that source this file
STAGES="dev staging prod-amer-east prod-amer-west prod-emea"

# Put the pinned CLIs first so the host kubectl/helm/kargo are never used by accident
case ":$PATH:" in
  *":$TOOLS_BIN:"*) ;;
  *) export PATH="$TOOLS_BIN:$PATH" ;;
esac

# --- Logging -------------------------------------------------------------------

if [[ -t 1 ]]; then
  _C_RED=$'\033[31m'
  _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'
  _C_BLUE=$'\033[34m'
  _C_RESET=$'\033[0m'
else
  _C_RED="" _C_GREEN="" _C_YELLOW="" _C_BLUE="" _C_RESET=""
fi

info() { printf '%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }
ok() { printf '%s ok %s %s\n' "$_C_GREEN" "$_C_RESET" "$*"; }
warn() { printf '%sWARN%s %s\n' "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
err() { printf '%sERROR%s %s\n' "$_C_RED" "$_C_RESET" "$*" >&2; }
die() {
  err "$*"
  exit 1
}

# --- Configuration -------------------------------------------------------------
# Files are parsed, never sourced: only KEY=value lines are read and nothing is executed.
# Precedence: variables already in the environment > .env > workshop.env > workshop.env.example > versions.env.
# workshop.env.example is the template (committed); workshop.env is the attendee's own copy (not in git) and is created from it
# the first time. The template is read first, so a setting added later still has its default in an older workshop.env.
# .env exists only on the workshop developers' machines; attendees edit workshop.env or pass VAR=value.

_ENV_PRESET=""
_ENV_ASSIGNED=" "
_ENV_LOADED=""

_env_assign() {
  local key="$1" val="$2"
  case "$_ENV_PRESET" in
    *" $key "*)
      case "$_ENV_ASSIGNED" in
        *" $key "*) ;; # set by an earlier file: a later file may override it
        *) return 0 ;; # set by the caller's environment: it wins over every file
      esac
      ;;
  esac
  export "$key=$val"
  _ENV_ASSIGNED="$_ENV_ASSIGNED$key "
}

_env_load_file() {
  local file="$1" line key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[2]}"
      val="${BASH_REMATCH[3]}"
      val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
      case "$val" in
        \"*\") val="${val#\"}" val="${val%\"}" ;;
        \'*\') val="${val#\'}" val="${val%\'}" ;;
      esac
      _env_assign "$key" "$val"
    fi
  done <"$file"
}

load_env() {
  [[ -z "$_ENV_LOADED" ]] || return 0
  _ENV_LOADED=1
  _ENV_PRESET=" $(compgen -e | tr '\n' ' ') "
  _env_load_file "$ROOT_DIR/versions.env"
  _env_load_file "$ROOT_DIR/workshop.env.example"
  if [[ ! -f "$ROOT_DIR/workshop.env" && -f "$ROOT_DIR/workshop.env.example" ]]; then
    cp "$ROOT_DIR/workshop.env.example" "$ROOT_DIR/workshop.env"
    printf 'Created workshop.env from workshop.env.example. It is yours: set WORKSHOP_PREFIX in it.\n' >&2
  fi
  _env_load_file "$ROOT_DIR/workshop.env"
  _env_load_file "$ROOT_DIR/.env"
  validate_env
}

validate_env() {
  case "${RELEASE_MODE:-}" in
    ghcr | registry) ;;
    *) die "RELEASE_MODE must be 'ghcr' or 'registry' (got '${RELEASE_MODE:-}')" ;;
  esac
  if [[ ! "${HTTP_PORT:-}" =~ ^[0-9]+$ ]] || ((HTTP_PORT < 1 || HTTP_PORT > 65535)); then
    die "HTTP_PORT must be a number between 1 and 65535 (got '${HTTP_PORT:-}')"
  fi
  local var
  for var in IMAGE_REGISTRY IMAGE_OWNER IMAGE_NAME WORKSHOP_DOMAIN CLUSTER_NAME; do
    [[ -n "${!var:-}" ]] || die "$var is empty (check workshop.env / .env)"
  done
  derive_instance_names
}

# --- The attendee's prefix and the names derived from it -------------------------------

# Prints what is wrong with WORKSHOP_PREFIX, or nothing when it is fine
prefix_problem() {
  if [[ -z "${WORKSHOP_PREFIX:-}" ]]; then
    printf 'WORKSHOP_PREFIX is not set. Set it in workshop.env to your first name or handle (example: anna)'
  elif [[ ! "$WORKSHOP_PREFIX" =~ ^[a-z][a-z0-9-]{0,11}$ || "$WORKSHOP_PREFIX" == *- ]]; then
    printf "WORKSHOP_PREFIX='%s' is not valid: use lowercase letters, digits and hyphens, start with a letter, at most 12 characters, no trailing hyphen (example: anna)" "$WORKSHOP_PREFIX"
  fi
}

# The two instances created on the platform are named <prefix>-workshop; empty until the prefix is valid
derive_instance_names() {
  if [[ -z "$(prefix_problem)" ]]; then
    export AKUITY_ARGOCD_INSTANCE="${WORKSHOP_PREFIX}-workshop"
    export AKUITY_KARGO_INSTANCE="${WORKSHOP_PREFIX}-workshop"
  else
    export AKUITY_ARGOCD_INSTANCE="" AKUITY_KARGO_INSTANCE=""
  fi
}

require_prefix() {
  local problem
  problem="$(prefix_problem)"
  [[ -z "$problem" ]] || die "$problem"
}

# --- Derived values: the only place that builds image repos and URLs -------------

# Where the images are published (the "CI output"); also the source for `release`/`prefetch`
image_repo_source() { printf '%s/%s/%s' "$IMAGE_REGISTRY" "$IMAGE_OWNER" "$IMAGE_NAME"; }

# The repo the Warehouse watches and the chart pulls from, according to RELEASE_MODE
image_repo_cluster() {
  case "$RELEASE_MODE" in
    ghcr) image_repo_source ;;
    registry) printf '%s/%s/%s' "$CLUSTER_REGISTRY" "$IMAGE_OWNER" "$IMAGE_NAME" ;;
  esac
}

# ":8080" when HTTP_PORT is not 80, empty otherwise
port_suffix() {
  if [[ "$HTTP_PORT" != "80" ]]; then
    printf ':%s' "$HTTP_PORT"
  fi
}

service_host() { printf '%s.%s' "$1" "$WORKSHOP_DOMAIN"; }
service_url() { printf 'http://%s%s' "$(service_host "$1")" "$(port_suffix)"; }

# --- Platform ------------------------------------------------------------------

detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'darwin' ;;
    Linux) printf 'linux' ;; # includes WSL2
    *) die "Unsupported OS '$(uname -s)'. Use macOS, Linux or Windows with WSL2." ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64 | aarch64) printf 'arm64' ;;
    x86_64 | amd64) printf 'amd64' ;;
    *) die "Unsupported CPU architecture '$(uname -m)'." ;;
  esac
}

# --- Cluster helpers -----------------------------------------------------------

require_docker() {
  have docker || die "Docker is not installed. Install Docker Desktop, Colima, Rancher Desktop or Docker Engine."
  docker info >/dev/null 2>&1 || die "The Docker daemon is not reachable. Start Docker and run again."
}

require_tools() {
  local tool
  for tool in kind kubectl helm; do
    [[ -x "$TOOLS_BIN/$tool" ]] || die "$tool is not installed in $TOOLS_BIN. Run: make tools"
  done
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; }

# Replaces every @@NAME@@ in a template file with the value of the environment variable NAME
render_template() {
  local file="$1" out name
  [[ -f "$file" ]] || die "template not found: $file"
  out="$(cat "$file")"
  for name in $(grep -o '@@[A-Z0-9_]*@@' "$file" | sort -u | tr -d '@'); do
    [[ -n "${!name+x}" ]] || die "$file uses @@$name@@ but $name is not set"
    out="${out//"@@$name@@"/${!name}}"
  done
  printf '%s\n' "$out"
}

# --- Akuity Platform -----------------------------------------------------------
# The akuity CLI keeps one global session in ~/.config/akuity. We never change its global configuration
# (`akuity config set`): every call names the server and the organization explicitly.

# True only when the session works. `akuity whoami` is not enough: it prints "Authenticated as ..." even when the
# token has expired, so the check is an authenticated call (listing the organizations).
akuity_logged_in() { akuity organization list --server "$AKUITY_SERVER_URL" >/dev/null 2>&1; }

# Lists the organizations of the logged-in account as "<name> <roles>" lines
akuity_orgs() {
  local out
  out="$(akuity organization list --server "$AKUITY_SERVER_URL" 2>&1)" ||
    die "Could not list your organizations on $AKUITY_SERVER_URL: $(printf '%s' "$out" | tail -1 | cut -c1-160). Run: make login"
  printf '%s\n' "$out" | awk 'NR>1 && NF>=2 {print $2, $3}'
}

# E-mail of the logged-in account (written into the description of the instances we create)
akuity_email() {
  akuity whoami --server "$AKUITY_SERVER_URL" 2>/dev/null | sed -n 's/^Authenticated as .*(\(.*\))$/\1/p' | head -1
}

# URL of an instance on the platform (<argocd|kargo> <instance name> <organization>), empty when it does not exist.
# The JSON of `instance get` carries a "hostname" such as <id>.cd.akuity.cloud or <id>.kargo.akuity.cloud.
akuity_instance_url() {
  local host
  host="$(akuity "$1" instance get "$2" --server "$AKUITY_SERVER_URL" --organization-name "$3" -o json 2>/dev/null |
    sed -n 's/.*"hostname": *"\([^"]*\)".*/\1/p' | head -1)"
  [[ -z "$host" ]] || printf 'https://%s' "$host"
}

# Prints the organization to use: AKUITY_ORGANIZATION, or the only one of the account
akuity_org() {
  local orgs count
  if [[ -n "${AKUITY_ORGANIZATION:-}" ]]; then
    akuity_orgs | awk -v o="$AKUITY_ORGANIZATION" '$1==o {f=1} END {exit !f}' ||
      die "Your account has no organization named '$AKUITY_ORGANIZATION' on $AKUITY_SERVER_URL. Check AKUITY_ORGANIZATION in workshop.env."
    printf '%s' "$AKUITY_ORGANIZATION"
    return 0
  fi
  orgs="$(akuity_orgs)"
  count="$(printf '%s\n' "$orgs" | grep -c . || true)"
  case "$count" in
    0) die "Your account belongs to no organization on $AKUITY_SERVER_URL." ;;
    1) printf '%s' "${orgs%% *}" ;;
    *) die "Your account belongs to several organizations ($(printf '%s' "$orgs" | awk '{printf "%s ", $1}')). Set AKUITY_ORGANIZATION in workshop.env." ;;
  esac
}

# --- Admin account of the instances --------------------------------------------------------
# The admin accounts are off on new instances. We enable them with one password for both: random unless
# WORKSHOP_ADMIN_PASSWORD is set, kept (with its bcrypt hash, so re-running changes nothing) in .tools/admin.env.
ADMIN_ENV="$TOOLS_DIR/admin.env"

# bcrypt hash ($2a$ form, accepted by Argo CD and Kargo) of $1: host htpasswd, or the same tool from a container
bcrypt_hash() {
  local h
  if have htpasswd; then
    h="$(htpasswd -nbBC 10 "" "$1" | tr -d ':\n')"
  else
    require_docker
    h="$(docker run --rm --entrypoint htpasswd "$HTPASSWD_IMAGE" -nbBC 10 "" "$1" | tr -d ':\n')"
  fi
  # shellcheck disable=SC2016 # the dollar signs are literal: a bcrypt hash starts with $2
  [[ "$h" == '$2'* ]] || die "Could not hash the admin password."
  printf '%s' "\$2a${h#\$2?}"
}

# Exports ADMIN_PASSWORD, ADMIN_PASSWORD_HASH (also in base64) and ADMIN_PASSWORD_MTIME, creating .tools/admin.env when needed
ensure_admin_credentials() {
  local want="${WORKSHOP_ADMIN_PASSWORD:-}" stored=""
  mkdir -p "$TOOLS_DIR"
  if [[ -f "$ADMIN_ENV" ]]; then
    stored="$(sed -n 's/^ADMIN_PASSWORD=//p' "$ADMIN_ENV")"
  fi
  if [[ -z "$stored" || ( -n "$want" && "$want" != "$stored" ) ]]; then
    [[ -n "$want" ]] || want="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
    (umask 077 && printf 'ADMIN_PASSWORD=%s\nADMIN_PASSWORD_HASH=%s\nADMIN_PASSWORD_MTIME=%s\n' \
      "$want" "$(bcrypt_hash "$want")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ADMIN_ENV")
  fi
  ADMIN_PASSWORD="$(sed -n 's/^ADMIN_PASSWORD=//p' "$ADMIN_ENV")"
  ADMIN_PASSWORD_HASH="$(sed -n 's/^ADMIN_PASSWORD_HASH=//p' "$ADMIN_ENV")"
  ADMIN_PASSWORD_MTIME="$(sed -n 's/^ADMIN_PASSWORD_MTIME=//p' "$ADMIN_ENV")"
  # Secret values are base64 in `data`, like any Kubernetes Secret (the platform rejects plain text)
  ADMIN_PASSWORD_HASH_B64="$(printf '%s' "$ADMIN_PASSWORD_HASH" | base64 | tr -d '\n')"
  export ADMIN_PASSWORD ADMIN_PASSWORD_HASH ADMIN_PASSWORD_MTIME ADMIN_PASSWORD_HASH_B64
}

# --- Gitea ----------------------------------------------------------------------------------
# The same URL works from the browser, from Kargo and from Argo CD (CoreDNS answers *.${WORKSHOP_DOMAIN}).
# shellcheck disable=SC2034 # used by the scripts that source this file
GITEA_ENV="$TOOLS_DIR/gitea.env" # password and token of the kargo-bot user

gitea_url() { service_url gitea; }
gitea_repo_url() { printf '%s/%s/%s' "$(gitea_url)" "$GITEA_ORG" "$GITEA_REPO"; }

# curl to Gitea that does not depend on public DNS: the host name is pinned to the local port
gitea_curl() { curl -sS -m 30 --resolve "$(service_host gitea):${HTTP_PORT}:127.0.0.1" "$@"; }

# gitea_api <method> <path> [curl options]: an administrator call, prints the body
gitea_api() {
  gitea_curl -u "$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD" -H 'Content-Type: application/json' \
    -X "$1" "$(gitea_url)/api/v1$2" "${@:3}"
}

# gitea_code <method> <path> [curl options]: prints the HTTP status only
gitea_code() { gitea_api "$1" "$2" -o /dev/null -w '%{http_code}' "${@:3}"; }

# --- Kargo CLI ----------------------------------------------------------------------------------
# The kargo CLI keeps its login in the home directory. Ours lives in .tools/kargo-home, so it never touches (or
# depends on) a kargo login of the attendee. Logging in uses the admin account of the instance.
KARGO_HOME="$TOOLS_DIR/kargo-home"

kargo_cli() { HOME="$KARGO_HOME" "$TOOLS_BIN/kargo" "$@"; }

# Address of the Kargo instance, kept in .tools/kargo-url so the labs do not need the Akuity session
kargo_url() {
  local url="" org
  if [[ -f "$TOOLS_DIR/kargo-url" && "${1:-}" != refresh ]]; then
    cat "$TOOLS_DIR/kargo-url"
    return 0
  fi
  akuity_logged_in || die "Cannot find your Kargo address: you are not logged in to $AKUITY_SERVER_URL. Run: make login"
  org="$(akuity_org)"
  url="$(akuity_instance_url kargo "$AKUITY_KARGO_INSTANCE" "$org")"
  [[ -n "$url" ]] || die "The Kargo instance '$AKUITY_KARGO_INSTANCE' does not exist. Run: make up"
  mkdir -p "$TOOLS_DIR"
  printf '%s' "$url" >"$TOOLS_DIR/kargo-url"
  printf '%s' "$url"
}

# Logs the CLI in to the workshop's Kargo instance with the admin account
kargo_login() {
  local url
  ensure_admin_credentials
  mkdir -p "$KARGO_HOME"
  url="$(kargo_url)"
  if ! kargo_cli login "$url" --admin --password "$ADMIN_PASSWORD" >/dev/null 2>&1; then
    # the address may be stale (instance recreated): ask the platform again, once
    url="$(kargo_url refresh)"
    kargo_cli login "$url" --admin --password "$ADMIN_PASSWORD" >/dev/null 2>&1 ||
      die "Could not log in to Kargo at $url as admin. Open the address in a browser: does it answer?"
  fi
}

# --- Release state ----------------------------------------------------------------------------
# `make release` moves the ceiling of the Warehouse's image constraint (RELEASE_MODE=ghcr). It is kept here so that
# the labs' catch-up and a reset render the same Warehouse.
RELEASE_FILE="$TOOLS_DIR/release"
FIRST_RELEASE=1.0.0 # the first version the Warehouse may select

# The catalog versions that are on the registry before the workshop: LIVE_VERSIONS are published by hand during Lab 6
prepublished_versions() {
  local v out=""
  for v in $CATALOG_VERSIONS; do
    case " ${LIVE_VERSIONS:-} " in *" $v "*) ;; *) out="$out $v" ;; esac
  done
  printf '%s' "${out# }"
}

release_ceiling() { if [[ -f "$RELEASE_FILE" ]]; then cat "$RELEASE_FILE"; else printf '%s' "$FIRST_RELEASE"; fi; }

# Renders steps/warehouse.yaml for a ceiling (default: the current one) to stdout
render_warehouse() {
  local ceiling="${1:-$(release_ceiling)}"
  export IMAGE_CONSTRAINT=">=$FIRST_RELEASE <=$ceiling" CLUSTER_IMAGE_REPO REFRESH_TOKEN GITEA_REPO_URL GITEA_BRANCH
  CLUSTER_IMAGE_REPO="$(image_repo_cluster)"
  REFRESH_TOKEN="$(date -u +%Y%m%dT%H%M%SZ)"
  GITEA_REPO_URL="$(gitea_repo_url)"
  render_template "$ROOT_DIR/steps/warehouse.yaml"
}

# --- Freight (needs a logged-in kargo CLI) -------------------------------------

# The name of the Freight with this image tag, once it is verified in the given Stage (empty until then)
freight_verified_in() { # <stage> <tag>
  kargo_cli get freight --project "$KARGO_PROJECT" \
    -o jsonpath='{range .items[*]}{.metadata.name} {.images[0].tag} {.status.verifiedIn.'"$1"'.verifiedAt}{"\n"}{end}' 2>/dev/null |
    awk -v tag="$2" '$2 == tag && NF >= 3 {print $1; exit}' || true
}
freight_is_verified() { [[ -n "$(freight_verified_in "$1" "$2")" ]]; }

# The newest image tag among the Freight of the project (empty when there is none)
newest_freight_tag() {
  kargo_cli get freight --project "$KARGO_PROJECT" -o jsonpath='{range .items[*]}{.images[0].tag}{"\n"}{end}' 2>/dev/null | sort -V | tail -1 || true
}

# A call to the Kargo API as the logged-in admin: kargo_api <method> <path> [json]; prints the answer
kargo_api() {
  local conf="$KARGO_HOME/.config/kargo/config" addr token args=()
  addr="$(sed -n 's/^apiAddress: *//p' "$conf")"
  token="$(sed -n 's/^bearerToken: *//p' "$conf")"
  [[ -n "${3:-}" ]] && args=(-d "$3")
  curl -sS -m 30 -X "$1" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    ${args[@]+"${args[@]}"} "$addr$2"
}

# --- The inbox of Lab 7 (webhook.site: an address that keeps what is sent to it; no account) -----
INBOX_FILE="$TOOLS_DIR/inbox"

# Creates an inbox and prints its id
inbox_create() {
  curl -s -m 20 -X POST https://webhook.site/token -H 'Content-Type: application/json' \
    -d '{"default_status":200,"default_content":"ok","default_content_type":"text/plain","expiry":true}' |
    sed -n 's/.*"uuid": *"\([0-9a-f-]*\)".*/\1/p' | head -1
}

# The id of the inbox in use: the one in the attendee's file, or the one catchup made
inbox_uuid() {
  local file="$ROOT_DIR/work/lab-7/message-channel.yaml" id=""
  [[ ! -f "$file" ]] || id="$(sed -n 's#^ *url: *https://webhook.site/\([0-9a-f-]*\).*#\1#p' "$file" | head -1)"
  if [[ -z "$id" && -f "$INBOX_FILE" ]]; then id="$(cat "$INBOX_FILE")"; fi
  printf '%s' "$id"
}

# Everything the inbox received, on one line (empty when nothing, or when it cannot be read)
inbox_content() { # <id>
  curl -s -m 20 "https://webhook.site/token/$1/requests?per_page=100" 2>/dev/null | tr -d '\n' || true
}

# --- AWS (Lab 11) ----------------------------------------------------------------------------

# The id of this attendee in AWS: the prefix plus four characters of a hash of the Akuity account email, so that two
# attendees with the same prefix do not share a Lambda or a state file. Stable: the same account gets the same id.
aws_participant() {
  local email hash
  email="$(akuity_email 2>/dev/null || true)"
  if [[ -z "$email" ]]; then
    printf '%s' "$WORKSHOP_PREFIX"
    return 0
  fi
  hash="$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]' | { shasum 2>/dev/null || sha1sum; } | cut -c1-4)"
  printf '%s-%s' "$WORKSHOP_PREFIX" "$hash"
}

# --- Small utilities -----------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

sha256_file() {
  if have sha256sum; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# True when something accepts TCP connections on 127.0.0.1:$1
port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# Outbound HTTPS probe. Prints "ok <http status>" when a TLS connection works (any HTTP status counts),
# or "fail <reason>" with a short human reason derived from curl's exit code.
probe_https() {
  local url="$1" code rc=0
  code="$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "$url" 2>/dev/null)" || rc=$?
  if ((rc == 0)); then
    printf 'ok %s' "$code"
    return 0
  fi
  case "$rc" in
    6) printf 'fail DNS lookup failed' ;;
    7) printf 'fail connection refused or blocked' ;;
    28) printf 'fail timed out (firewall or slow network)' ;;
    35 | 51 | 58 | 60 | 77 | 83) printf 'fail TLS certificate problem (corporate proxy that re-signs HTTPS?)' ;;
    *) printf 'fail curl error %s' "$rc" ;;
  esac
}

# Epoch seconds of an HTTP Date header value ("Fri, 23 Oct 2026 08:28:34 GMT"), or nothing
http_date_epoch() {
  local s="$1"
  date -u -d "$s" +%s 2>/dev/null || date -j -u -f '%a, %d %b %Y %H:%M:%S GMT' "$s" +%s 2>/dev/null || true
}

# Prints the first IPv4 address of a host name, or nothing
resolve_ipv4() {
  local host="$1" ip=""
  if have getent; then
    ip="$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')"
  fi
  if [[ -z "$ip" ]] && have dscacheutil; then
    ip="$(dscacheutil -q host -a name "$host" 2>/dev/null | awk '/^ip_address:/{print $2; exit}')"
  fi
  if [[ -z "$ip" ]] && have host; then
    ip="$(host -t A "$host" 2>/dev/null | awk '/has address/{print $NF; exit}')"
  fi
  printf '%s' "$ip"
}
