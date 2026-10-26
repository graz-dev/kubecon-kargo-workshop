#!/usr/bin/env bash
# Makes an image version visible to the Warehouse: the "developer's CI shipped a new release" moment.
# In RELEASE_MODE=ghcr every version is already on ghcr.io, so this moves the ceiling of the Warehouse's image
# constraint (">=1.0.0 <=VERSION") and changes its refresh annotation, which makes Kargo look at once.
# If the Warehouse does not exist yet (before Lab 1) it only records the ceiling, and Lab 1 creates the Warehouse with it.
#
#   scripts/release.sh VERSION       SKIP_PLATFORM=1 only records the ceiling; DRY_RUN=1 shows what it would apply
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/seed.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/seed.sh"
load_env

VERSION="${1:-}"
[[ -n "$VERSION" ]] || die "Say which version, for example: make release VERSION=1.1.0 (catalog: $CATALOG_VERSIONS)"
DRY_RUN="${DRY_RUN:-0}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ "$RELEASE_MODE" == ghcr ]] || die "RELEASE_MODE=$RELEASE_MODE is not implemented yet: only 'ghcr' works (the local registry comes later)."
case " $CATALOG_VERSIONS " in
  *" $VERSION "*) ;;
  *) die "Version '$VERSION' is not in the catalog ($CATALOG_VERSIONS)." ;;
esac
[[ "$(printf '%s\n%s\n' "$FIRST_RELEASE" "$VERSION" | sort -V | head -1)" == "$FIRST_RELEASE" ]] ||
  die "$VERSION is older than $FIRST_RELEASE: the Warehouse only selects $FIRST_RELEASE and newer (0.9.0 is what runs before Kargo)."

# The version must really be there, or the Warehouse would wait for nothing (anonymous, like the attendees)
if [[ -x "$TOOLS_BIN/crane" ]]; then
  cfg="$(mktemp -d)"
  DOCKER_CONFIG="$cfg" crane manifest "$(image_repo_cluster):$VERSION" >/dev/null 2>&1 ||
    { rm -rf "$cfg"; die "$(image_repo_cluster):$VERSION cannot be pulled anonymously. Is it published and public? (make doctor)"; }
  rm -rf "$cfg"
fi

if [[ "$DRY_RUN" == 1 ]]; then
  info "dry run: the ceiling would become $VERSION (the Warehouse would select >=$FIRST_RELEASE <=$VERSION)"
else
  mkdir -p "$TOOLS_DIR"
  printf '%s' "$VERSION" >"$RELEASE_FILE"
  ok "release ceiling is now $VERSION (the Warehouse selects >=$FIRST_RELEASE <=$VERSION)"
fi

[[ "${SKIP_PLATFORM:-0}" != 1 ]] || exit 0
platform_preflight
if akuity kargo export "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG" 2>/dev/null | grep -q '^kind: Warehouse'; then
  render_warehouse "$VERSION" >"$WORK/warehouse.yaml"
  mkdir -p "$WORK/wh"
  mv "$WORK/warehouse.yaml" "$WORK/wh/warehouse.yaml"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] akuity kargo apply -f <the Warehouse below> --name %s\n' "$KARGO"
    sed 's/^/      | /' "$WORK/wh/warehouse.yaml"
  else
    akuity kargo apply -f "$WORK/wh" --name "$KARGO" --server "$AKUITY_SERVER_URL" --organization-name "$ORG"
    ok "the Warehouse sees $VERSION: new Freight appears in a moment"
  fi
else
  info "no Warehouse in the Kargo instance yet: the ceiling will be used when it is created"
fi
