#!/usr/bin/env bash
# Turns the Promotion Controller of your Kargo instance on or off. Custom promotion steps need it (Lab 10): with it on, every
# promotion runs in a pod of the Kargo agent. `make reset` turns it off again. Only that one setting of the instance changes.
#
#   scripts/promotion-controller.sh on|off|status
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/seed.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/seed.sh"
load_env
require_tools

WANT="${1:-}"
case "$WANT" in on | off | status) ;; *) die "Say on, off or status: make promotion-controller STATE=on" ;; esac
DRY_RUN=0
platform_preflight

if [[ "$WANT" == status ]]; then
  promotion_controller_enabled && echo on || echo off
  exit 0
fi
set_promotion_controller "$WANT"
