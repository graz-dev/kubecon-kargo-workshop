#!/usr/bin/env bash
# Syntax-checks every script with `bash -n`, then runs shellcheck and yamllint when they are installed.
# Both linters are maintainer tools: they are not pinned and not required to run the workshop.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

cd "$ROOT_DIR"
SCRIPTS=()
while IFS= read -r f; do
  SCRIPTS+=("$f")
done < <(find scripts -type f -name '*.sh' | sort)

info "bash -n (${#SCRIPTS[@]} scripts)"
for f in "${SCRIPTS[@]}"; do
  bash -n "$f"
done
ok "syntax"

if have shellcheck; then
  info "shellcheck"
  shellcheck "${SCRIPTS[@]}"
  ok "shellcheck"
else
  warn "shellcheck not installed: skipped"
fi

if have yamllint; then
  info "yamllint"
  yamllint -c .yamllint.yml .
  ok "yamllint"
else
  warn "yamllint not installed: skipped"
fi

# Every lab skeleton must equal its solution (steps/<N>/), except on the lines the attendee fills in (TODO)
load_env
info "lab skeletons against their solutions"
strip() { sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d; /^[[:space:]]*$/d' "$1"; }
export GITEA_REPO_URL CLUSTER_IMAGE_REPO
GITEA_REPO_URL="$(gitea_repo_url)"
CLUSTER_IMAGE_REPO="$(image_repo_cluster)"
for sk in workshop/lab-*/*.yaml; do
  [[ -f "$sk" ]] || continue
  lab="${sk#workshop/lab-}"
  lab="${lab%%/*}"
  sol="steps/$lab/$(basename "$sk")"
  [[ -f "$sol" ]] || die "$sk has no solution at $sol"
  render_template "$ROOT_DIR/$sol" >"${TMPDIR:-/tmp}/lint-solution.yaml"
  if ! awk -v sk="$sk" '
    NR == FNR { sol[FNR] = $0; n = FNR; next }
    { m++; if ($0 != sol[FNR] && $0 !~ /TODO/) { printf "%s line %d differs from the solution: %s\n", sk, FNR, $0; bad = 1 } }
    END { if (m != n) { printf "%s has %d lines, the solution %d\n", sk, m, n; bad = 1 } exit bad }
  ' <(strip "${TMPDIR:-/tmp}/lint-solution.yaml") <(strip "$sk"); then
    die "$sk and $sol are out of step"
  fi
done
ok "skeletons match their solutions"
