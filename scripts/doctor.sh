#!/usr/bin/env bash
# Pre-flight checks for running the workshop on this machine. Read-only: it changes nothing.
# Exit code 1 when at least one check FAILs (WARN and INFO never fail).
#
#   scripts/doctor.sh [--skip-images]
#
# DOCTOR_REPORT_FILE=<path> also writes a plain-text copy of every line (used by `make bootstrap`).
# The thresholds come from `make measure` on a complete environment (all the labs done): see the README.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

SKIP_IMAGES=0
for arg in "$@"; do
  case "$arg" in
    --skip-images) SKIP_IMAGES=1 ;;
    -h | --help)
      sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument '$arg'" ;;
  esac
done

FAILS=0
WARNS=0
REPORT_FILE="${DOCTOR_REPORT_FILE:-}"

row() { # row <OK|WARN|FAIL|INFO> <label> [detail]
  local level="$1" label="$2" detail="${3:-}" color="$_C_RESET"
  case "$level" in
    OK) color="$_C_GREEN" ;;
    WARN)
      color="$_C_YELLOW"
      WARNS=$((WARNS + 1))
      ;;
    FAIL)
      color="$_C_RED"
      FAILS=$((FAILS + 1))
      ;;
    INFO) color="$_C_BLUE" ;;
  esac
  printf '[%s%-4s%s] %-26s %s\n' "$color" "$level" "$_C_RESET" "$label" "$detail"
  if [[ -n "$REPORT_FILE" ]]; then
    printf '[%-4s] %-26s %s\n' "$level" "$label" "$detail" >>"$REPORT_FILE"
  fi
}

section() {
  printf '\n%s\n' "$1"
  if [[ -n "$REPORT_FILE" ]]; then
    printf '\n%s\n' "$1" >>"$REPORT_FILE"
  fi
}

# --- Host prerequisites -----------------------------------------------------------

check_host() {
  section "Host"
  local os arch missing="" cmd
  os="$(detect_os)"
  arch="$(detect_arch)"
  row OK "platform" "$os/$arch"
  for cmd in git make bash curl; do
    have "$cmd" || missing="$missing $cmd"
  done
  if [[ -n "$missing" ]]; then
    row FAIL "host commands" "missing:$missing"
  else
    row OK "host commands" "git make bash curl"
  fi
  check_files
}

# A clone made with Windows line endings breaks every script; on WSL, a folder on the Windows disk is slow and loses permissions
check_files() {
  local crlf
  crlf="$(grep -l $'\r' "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/scripts/lib/*.sh "$ROOT_DIR"/Makefile 2>/dev/null | head -1 || true)"
  if [[ -n "$crlf" ]]; then
    row FAIL "line endings" "${crlf#"$ROOT_DIR"/} has Windows line endings. Clone again inside WSL, or run: git config --global core.autocrlf false, then clone again"
  else
    row OK "line endings" "Unix"
  fi
  if grep -qi microsoft /proc/version 2>/dev/null && [[ "$ROOT_DIR" == /mnt/* ]]; then
    row WARN "folder" "$ROOT_DIR is on the Windows disk: it is slow and loses file permissions. Clone it in your Linux home instead"
  fi
}

# --- Your settings ------------------------------------------------------------------

check_settings() {
  section "Your settings"
  local problem
  problem="$(prefix_problem)"
  if [[ -n "$problem" ]]; then
    row FAIL "WORKSHOP_PREFIX" "$problem"
  else
    row OK "WORKSHOP_PREFIX" "$WORKSHOP_PREFIX (your instances on the platform: ${AKUITY_ARGOCD_INSTANCE})"
  fi
}

# --- Docker -------------------------------------------------------------------------

DOCKER_OK=0

check_docker() {
  section "Docker"
  if ! have docker; then
    row FAIL "docker CLI" "not found. Install Docker Desktop, Colima, Rancher Desktop or Docker Engine"
    return 0
  fi
  local info rest server mem_bytes cpus cgroup security mem_gb
  if ! info="$(docker info --format '{{.ServerVersion}}|{{.MemTotal}}|{{.NCPU}}|{{.CgroupVersion}}|{{.SecurityOptions}}' 2>/dev/null)"; then
    row FAIL "docker daemon" "not reachable. Start Docker and run again"
    return 0
  fi
  DOCKER_OK=1
  server="${info%%|*}"
  rest="${info#*|}"
  mem_bytes="${rest%%|*}"
  rest="${rest#*|}"
  cpus="${rest%%|*}"
  rest="${rest#*|}"
  cgroup="${rest%%|*}"
  security="${rest#*|}"
  row OK "docker daemon" "server $server"

  mem_gb="$(awk -v b="$mem_bytes" 'BEGIN{printf "%.1f", b/1073741824}')"
  if awk -v m="$mem_gb" -v t="$DOCTOR_MIN_MEM_GB" 'BEGIN{exit !(m < t)}'; then
    row FAIL "docker memory" "${mem_gb} GiB available, at least ${DOCTOR_MIN_MEM_GB} needed. Raise it in Docker settings"
  elif awk -v m="$mem_gb" -v t="$DOCTOR_WARN_MEM_GB" 'BEGIN{exit !(m < t)}'; then
    row WARN "docker memory" "${mem_gb} GiB available; ${DOCTOR_WARN_MEM_GB}+ recommended"
  else
    row OK "docker memory" "${mem_gb} GiB"
  fi

  if ((cpus < DOCTOR_MIN_CPUS)); then
    row WARN "docker cpus" "$cpus available; ${DOCTOR_MIN_CPUS}+ recommended"
  else
    row OK "docker cpus" "$cpus"
  fi

  # Kubernetes 1.35+ node images dropped cgroup v1 (kind v0.31.0 release notes)
  if [[ "$cgroup" == "1" ]]; then
    row FAIL "docker cgroup" "cgroup v1: Kubernetes 1.35 nodes need cgroup v2 (use a newer kernel/Docker setup)"
  elif [[ -n "$cgroup" ]]; then
    row OK "docker cgroup" "v$cgroup"
  fi

  if [[ "$security" == *rootless* && "$(uname -s)" == "Linux" && "$HTTP_PORT" -lt 1024 ]]; then
    row WARN "rootless docker" "ports below 1024 usually need root: set HTTP_PORT=8080 in workshop.env"
  fi
}

# Linux hosts running Docker natively: kind nodes need more inotify resources than the distro defaults
# (kind known issues: max_user_watches=524288, max_user_instances=512)
check_inotify() {
  local w="/proc/sys/fs/inotify/max_user_watches" i="/proc/sys/fs/inotify/max_user_instances" watches inst
  [[ "$(uname -s)" == "Linux" && -r "$w" && -r "$i" ]] || return 0
  watches="$(cat "$w")"
  inst="$(cat "$i")"
  if ((watches < 524288 || inst < 512)); then
    row WARN "inotify limits" "watches=$watches instances=$inst; kind may fail with 'too many open files'. Run: sudo sysctl fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512"
  else
    row OK "inotify limits" "watches=$watches instances=$inst"
  fi
}

check_disk() {
  local free_kb free_gb
  free_kb="$(df -Pk "$ROOT_DIR" | awk 'NR==2{print $4}')"
  free_gb="$(awk -v k="$free_kb" 'BEGIN{printf "%.0f", k/1048576}')"
  if ((free_gb < DOCTOR_MIN_DISK_GB)); then
    row WARN "free disk" "${free_gb} GiB on this filesystem; ${DOCTOR_MIN_DISK_GB}+ recommended"
  else
    row OK "free disk" "${free_gb} GiB on this filesystem"
  fi
}

# --- Local network ------------------------------------------------------------------

check_port() {
  section "Local network"
  if ! port_in_use "$HTTP_PORT"; then
    row OK "port $HTTP_PORT" "free on 127.0.0.1"
    return 0
  fi
  if [[ "$DOCKER_OK" == 1 ]] &&
    docker ps --filter "name=${CLUSTER_NAME}-control-plane" --format '{{.Ports}}' 2>/dev/null |
    grep -q ":${HTTP_PORT}->"; then
    row OK "port $HTTP_PORT" "in use by the workshop cluster '$CLUSTER_NAME'"
  else
    row FAIL "port $HTTP_PORT" "already in use. Free it or set HTTP_PORT=8080 in workshop.env"
  fi
}

check_dns() {
  local probe ip
  probe="$(service_host doctor-probe)"
  ip="$(resolve_ipv4 "$probe")"
  if [[ "$ip" == "127.0.0.1" ]]; then
    row OK "dns $WORKSHOP_DOMAIN" "$probe -> 127.0.0.1"
  elif [[ -z "$ip" ]]; then
    row FAIL "dns $WORKSHOP_DOMAIN" "$probe does not resolve (offline, or a resolver blocks it?). Gitea and the apps need it"
  else
    row FAIL "dns $WORKSHOP_DOMAIN" "$probe -> $ip, expected 127.0.0.1 (DNS rebinding protection on your router/VPN?)"
  fi
}

# --- Internet: the Akuity Platform, registries and download hosts ---------------------

# probe_row <label> <url> <FAIL|WARN> <purpose>
probe_row() {
  local label="$1" url="$2" level="$3" purpose="$4" res code
  res="$(probe_https "$url")"
  if [[ "$res" == ok* ]]; then
    code="${res#ok }"
    case "$code" in
      401 | 403 | 404) row OK "$label" "reachable (HTTP $code is its normal answer to an anonymous request) - $purpose" ;;
      *) row OK "$label" "reachable (HTTP $code) - $purpose" ;;
    esac
  else
    row "$level" "$label" "${res#fail } - needed for: $purpose"
  fi
}

check_internet() {
  section "Internet (outbound HTTPS)"
  local platform_host var proxies=""
  platform_host="${AKUITY_SERVER_URL#*://}"
  platform_host="${platform_host%%/*}"
  probe_row "$platform_host" "$AKUITY_SERVER_URL" FAIL "Akuity Platform (Kargo and Argo CD)"
  probe_row "ghcr.io" "https://ghcr.io/v2/" FAIL "workshop images"
  probe_row "registry-1.docker.io" "https://registry-1.docker.io/v2/" FAIL "cluster images (Docker Hub)"
  probe_row "quay.io" "https://quay.io/v2/" FAIL "Akuity and Argo agent images"
  probe_row "docker.gitea.com" "https://docker.gitea.com/v2/" WARN "the Gitea image"
  probe_row "dl.akuity.io" "https://dl.akuity.io" WARN "downloading the akuity CLI"
  probe_row "github.com" "https://github.com" WARN "downloading the kargo and crane CLIs"
  # What the later labs download while they run: better to know now than in the middle of a lab
  probe_row "mirror.gcr.io" "https://mirror.gcr.io/v2/" WARN "the Trivy vulnerability database (Lab 10)"
  probe_row "webhook.site" "https://webhook.site" WARN "the inbox that receives the notifications (Lab 7)"
  probe_row "registry.opentofu.org" "https://registry.opentofu.org/.well-known/terraform.json" WARN "the OpenTofu providers (Lab 11)"
  probe_row "lambda.${AWS_REGION:-us-east-1}.amazonaws.com" "https://lambda.${AWS_REGION:-us-east-1}.amazonaws.com/" WARN "AWS Lambda (Lab 11)"
  probe_row "s3.${AWS_REGION:-us-east-1}.amazonaws.com" "https://s3.${AWS_REGION:-us-east-1}.amazonaws.com/" WARN "the Terraform state on AWS S3 (Lab 11)"
  probe_row "service-now.com" "https://service-now.com" WARN "ServiceNow (Lab 12)"

  for var in HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy; do
    if [[ -n "${!var:-}" ]]; then
      proxies="$proxies $var"
    fi
  done
  if [[ -n "$proxies" ]]; then
    row INFO "proxy variables" "set:$proxies (Docker and the cluster need the proxy configured too)"
  fi

  check_clock
  check_dockerhub_limit
}

# TLS and login tokens break when the local clock is off
check_clock() {
  local hdr server_epoch skew
  hdr="$(curl -sI -m 10 https://ghcr.io/v2/ 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="date"{print $2; exit}')"
  [[ -n "$hdr" ]] || return 0
  server_epoch="$(http_date_epoch "$hdr")"
  [[ -n "$server_epoch" ]] || return 0
  skew=$(($(date -u +%s) - server_epoch))
  ((skew < 0)) && skew=$((-skew))
  if ((skew > DOCTOR_MAX_CLOCK_SKEW)); then
    row WARN "clock" "off by ${skew}s compared with the internet; enable automatic date and time"
  else
    row OK "clock" "within ${skew}s of the internet"
  fi
}

# Anonymous Docker Hub pulls are limited per IP; a venue network shares one IP among many laptops
check_dockerhub_limit() {
  local token hdr remaining
  token="$(curl -fsS -m 10 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull' 2>/dev/null |
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  [[ -n "$token" ]] || return 0
  hdr="$(curl -fsSI -m 10 -H "Authorization: Bearer $token" \
    https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>/dev/null | tr -d '\r')"
  remaining="$(printf '%s\n' "$hdr" | sed -n 's/^[Rr]atelimit-remaining: *\([0-9]*\).*/\1/p' | head -1)"
  [[ -n "$remaining" ]] || return 0
  if ((remaining < DOCTOR_MIN_DOCKERHUB_PULLS)); then
    row WARN "docker hub pulls" "only $remaining anonymous pulls left for this IP; pull the images before the workshop"
  else
    row OK "docker hub pulls" "$remaining anonymous pulls left for this IP"
  fi
}

# --- Tools and images ---------------------------------------------------------------

check_tools() {
  section "Pinned tools (./.tools/bin)"
  local tool stamp want have_ver os arch
  os="$(detect_os)"
  arch="$(detect_arch)"
  for tool in kind kubectl helm kargo akuity crane; do
    stamp="$TOOLS_DIR/.stamps/$tool"
    case "$tool" in
      kind) want="$KIND_VERSION" ;;
      kubectl) want="$KUBECTL_VERSION" ;;
      helm) want="$HELM_VERSION" ;;
      kargo) want="$KARGO_VERSION" ;;
      akuity) want="$AKUITY_CLI_VERSION" ;;
      crane) want="$CRANE_VERSION" ;;
    esac
    have_ver=""
    if [[ -x "$TOOLS_BIN/$tool" && -f "$stamp" ]]; then
      have_ver="$(cat "$stamp")"
    fi
    if [[ "$have_ver" == "$want $os-$arch" ]]; then
      row OK "$tool" "$want"
    else
      row FAIL "$tool" "not installed at the pinned version $want. Run: make tools"
    fi
  done
}

check_images() {
  section "Images ($(image_repo_source))"
  if [[ "$SKIP_IMAGES" == 1 || "$DOCTOR_IMAGE_CHECK" == "skip" ]]; then
    row INFO "image catalog" "check skipped"
    return 0
  fi
  local level="WARN" repo tags missing="" v cfg manifest
  [[ "$DOCTOR_IMAGE_CHECK" == "fail" ]] && level="FAIL"
  if [[ ! -x "$TOOLS_BIN/crane" ]]; then
    row INFO "image catalog" "crane not installed yet (run: make tools)"
    return 0
  fi
  repo="$(image_repo_source)"
  # Anonymous access, exactly like an attendee: ignore any docker credentials on this machine
  cfg="$(mktemp -d)"
  if ! tags="$(DOCKER_CONFIG="$cfg" crane ls "$repo" 2>/dev/null)"; then
    rm -rf "$cfg"
    row "$level" "image catalog" "cannot list tags of $repo anonymously (not published yet, package private, or no network)"
    return 0
  fi
  for v in $(prepublished_versions); do
    printf '%s\n' "$tags" | grep -qx "$v" || missing="$missing $v"
  done
  if [[ -n "$missing" ]]; then
    row "$level" "image catalog" "tags missing from $repo:$missing"
  else
    row OK "image catalog" "all of: $(prepublished_versions) (${LIVE_VERSIONS:-none} is published live in Lab 6)"
  fi
  if manifest="$(DOCKER_CONFIG="$cfg" crane manifest "$repo:$INITIAL_VERSION" 2>/dev/null)"; then
    if printf '%s' "$manifest" | grep -Eq '"architecture": *"amd64"' &&
      printf '%s' "$manifest" | grep -Eq '"architecture": *"arm64"'; then
      row OK "multi-arch" "$INITIAL_VERSION has linux/amd64 and linux/arm64"
    else
      row "$level" "multi-arch" "$repo:$INITIAL_VERSION is not published for both amd64 and arm64"
    fi
  fi
  rm -rf "$cfg"
}

# --- Existing state -----------------------------------------------------------------

check_state() {
  section "State"
  row INFO "images" "$(image_repo_cluster)"
  if [[ "$DOCKER_OK" == 1 && -x "$TOOLS_BIN/kind" ]]; then
    if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
      row INFO "cluster" "'$CLUSTER_NAME' exists"
    else
      row INFO "cluster" "'$CLUSTER_NAME' not created yet (make up)"
    fi
  fi
  if [[ -x "$TOOLS_BIN/akuity" ]]; then
    if akuity_logged_in; then
      row INFO "akuity login" "$(akuity whoami --server "$AKUITY_SERVER_URL" 2>&1 | head -1)"
    else
      row INFO "akuity login" "not logged in to $AKUITY_SERVER_URL (make login, needed before make up)"
    fi
  fi
  row INFO "gitea URL" "$(service_url gitea)"
}

printf 'Workshop doctor (%s)\n' "$ROOT_DIR"
check_host
check_settings
check_docker
check_inotify
check_disk
check_port
check_dns
check_internet
check_tools
check_images
check_state

printf '\n'
if ((FAILS > 0)); then
  printf '%s%d check(s) failed%s, %d warning(s). Fix the FAIL lines above and run again.\n' "$_C_RED" "$FAILS" "$_C_RESET" "$WARNS"
  exit 1
fi
printf '%sReady%s (%d warning(s)).\n' "$_C_GREEN" "$_C_RESET" "$WARNS"
