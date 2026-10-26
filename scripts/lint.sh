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
