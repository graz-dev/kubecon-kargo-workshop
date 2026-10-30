#!/usr/bin/env bash
# Logs in to the Akuity Platform with the akuity CLI and checks the organization. Read-only on the platform.
# The login is the one interactive step of the whole workshop: the CLI prints a link and a code to open in the browser.
# Safe to run again: if you are already logged in it only shows who you are.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
[[ -x "$TOOLS_BIN/akuity" ]] || die "The akuity CLI is not installed in $TOOLS_BIN. Run: make tools"
[[ -n "${AKUITY_SERVER_URL:-}" ]] || die "AKUITY_SERVER_URL is not set. Set it in workshop.env to the URL of your Akuity Platform (example: https://akuity.cloud)"

if akuity_logged_in; then
  ok "already logged in to $AKUITY_SERVER_URL"
else
  # Not logged in, the session expired (it lasts about 12 hours), or there is no network
  info "No valid session on $AKUITY_SERVER_URL: logging in. Open the link the CLI prints and enter the code"
  akuity login --server "$AKUITY_SERVER_URL"
  akuity_logged_in || die "Login did not complete. Run 'make login' again."
fi
akuity whoami --server "$AKUITY_SERVER_URL"

org="$(akuity_org)"
ok "organization: $org"
printf '\nNext: make up\n'
