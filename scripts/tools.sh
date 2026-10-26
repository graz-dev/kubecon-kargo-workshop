#!/usr/bin/env bash
# Downloads the pinned CLIs into ./.tools/bin (right OS/arch) and checks that each one runs.
# Idempotent: a tool is skipped when its version stamp already matches versions.env.
#
#   scripts/tools.sh [install] [tool...]   install all tools, or only the named ones
#   scripts/tools.sh list                  show pinned vs installed versions
#   scripts/tools.sh path                  print the bin directory
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

ALL_TOOLS="kind kubectl helm kargo akuity crane"
STAMP_DIR="$TOOLS_DIR/.stamps"

tool_version() {
  case "$1" in
    kind) printf '%s' "$KIND_VERSION" ;;
    kubectl) printf '%s' "$KUBECTL_VERSION" ;;
    helm) printf '%s' "$HELM_VERSION" ;;
    kargo) printf '%s' "$KARGO_VERSION" ;;
    akuity) printf '%s' "$AKUITY_CLI_VERSION" ;;
    crane) printf '%s' "$CRANE_VERSION" ;;
    *) die "Unknown tool '$1' (known: $ALL_TOOLS)" ;;
  esac
}

# URL of the download for tool/os/arch
tool_url() {
  local tool="$1" ver="$2" os="$3" arch="$4" crane_os crane_arch
  case "$tool" in
    kind) printf 'https://kind.sigs.k8s.io/dl/v%s/kind-%s-%s' "$ver" "$os" "$arch" ;;
    kubectl) printf 'https://dl.k8s.io/release/v%s/bin/%s/%s/kubectl' "$ver" "$os" "$arch" ;;
    helm) printf 'https://get.helm.sh/helm-v%s-%s-%s.tar.gz' "$ver" "$os" "$arch" ;;
    kargo) printf 'https://github.com/akuity/kargo/releases/download/v%s/kargo-%s-%s' "$ver" "$os" "$arch" ;;
    akuity) printf 'https://dl.akuity.io/akuity-cli/v%s/%s/%s/akuity' "$ver" "$os" "$arch" ;;
    crane)
      crane_os="Linux"
      [[ "$os" == "darwin" ]] && crane_os="Darwin"
      crane_arch="x86_64"
      [[ "$arch" == "arm64" ]] && crane_arch="arm64"
      printf 'https://github.com/google/go-containerregistry/releases/download/v%s/go-containerregistry_%s_%s.tar.gz' \
        "$ver" "$crane_os" "$crane_arch"
      ;;
  esac
}

# Runs the tool once: catches a truncated download or a binary for the wrong architecture
smoke_test() {
  case "$1" in
    kind) "$TOOLS_BIN/kind" version ;;
    kubectl) "$TOOLS_BIN/kubectl" version --client ;;
    helm) "$TOOLS_BIN/helm" version --short ;;
    kargo) "$TOOLS_BIN/kargo" version --client ;;
    akuity) "$TOOLS_BIN/akuity" version ;;
    crane) "$TOOLS_BIN/crane" version ;;
  esac
}

install_tool() {
  local tool="$1" ver os arch want stamp url tmp src rc code
  ver="$(tool_version "$tool")"
  os="$(detect_os)"
  arch="$(detect_arch)"
  want="$ver $os-$arch"
  stamp="$STAMP_DIR/$tool"

  if [[ -x "$TOOLS_BIN/$tool" && -f "$stamp" && "$(cat "$stamp")" == "$want" ]]; then
    ok "$tool $ver already installed"
    return 0
  fi

  url="$(tool_url "$tool" "$ver" "$os" "$arch")"
  mkdir -p "$TOOLS_BIN" "$STAMP_DIR" "$TOOLS_DIR/tmp"
  tmp="$(mktemp -d "$TOOLS_DIR/tmp/$tool.XXXXXX")"

  info "Downloading $tool $ver ($os/$arch)"
  rc=0
  code="$(curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/download" -w '%{http_code}' "$url" 2>/dev/null)" || rc=$?
  if ((rc != 0)) && [[ "$code" =~ ^[45][0-9][0-9]$ ]]; then
    die "The server answered HTTP $code for $url (is $tool $ver still published?)"
  elif ((rc != 0)); then
    die "Could not download $url (no network, or a proxy/firewall blocks it). Run again when online: tools are cached in $TOOLS_BIN"
  fi

  case "$tool" in
    helm)
      tar -xzf "$tmp/download" -C "$tmp" "$os-$arch/helm"
      src="$tmp/$os-$arch/helm"
      ;;
    crane)
      tar -xzf "$tmp/download" -C "$tmp" crane
      src="$tmp/crane"
      ;;
    *) src="$tmp/download" ;;
  esac

  install -m 0755 "$src" "$TOOLS_BIN/$tool.new"
  mv -f "$TOOLS_BIN/$tool.new" "$TOOLS_BIN/$tool"
  rm -rf "$tmp"
  if ! smoke_test "$tool" >/dev/null 2>&1; then
    rm -f "$TOOLS_BIN/$tool" "$stamp"
    die "$tool $ver was downloaded but does not run on this machine ($os/$arch)"
  fi
  printf '%s' "$want" >"$stamp"
  ok "$tool $ver installed in $TOOLS_BIN"
}

list_tools() {
  local tool stamp have_ver
  printf '%-8s %-10s %s\n' TOOL PINNED INSTALLED
  for tool in $ALL_TOOLS; do
    stamp="$STAMP_DIR/$tool"
    have_ver="-"
    if [[ -x "$TOOLS_BIN/$tool" && -f "$stamp" ]]; then
      have_ver="$(cut -d' ' -f1 "$stamp")"
    fi
    printf '%-8s %-10s %s\n' "$tool" "$(tool_version "$tool")" "$have_ver"
  done
}

cmd="${1:-install}"
case "$cmd" in
  install)
    trap 'rm -rf "$TOOLS_DIR/tmp"' EXIT
    shift || true
    have curl || die "curl is required"
    if (($# == 0)); then
      # shellcheck disable=SC2086 # ALL_TOOLS is a space-separated list of simple words
      set -- $ALL_TOOLS
    fi
    for tool in "$@"; do
      install_tool "$tool"
    done
    ;;
  list) list_tools ;;
  path) printf '%s\n' "$TOOLS_BIN" ;;
  -h | --help | help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "Unknown command '$cmd' (try: install, list, path)" ;;
esac
