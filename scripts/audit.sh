#!/usr/bin/env bash
# Lists the audit events of the project: who did what, and why. Read-only.
# Events come from the record-audit-event step of a promotion, and are also in the Events tab of the project in the Kargo UI.
#
#   scripts/audit.sh
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools
kargo_login

events="$(kargo_api GET "/v1beta1/projects/$KARGO_PROJECT/events" | sed 's/{"kind":"Event"/\n&/g' | grep '"reason":"CustomAuditEvent"' || true)"
[[ -n "$events" ]] || die "No audit events yet. They appear when a promotion runs the record-audit-event step (Lab 9)."
printf '%-21s %-8s %-9s %-8s %s\n' WHEN WHO WHAT STAGE MESSAGE
while IFS= read -r line; do
  when="$(sed -n 's/.*"creationTimestamp":"\([^"]*\)".*/\1/p' <<<"$line" | head -1)"
  who="$(sed -n 's/.*"ee.kargo.akuity.io\/actor":"\([^"]*\)".*/\1/p' <<<"$line")"
  what="$(sed -n 's/.*"ee.kargo.akuity.io\/audit-event-type":"\([^"]*\)".*/\1/p' <<<"$line")"
  stage="$(sed -n 's/.*"ee.kargo.akuity.io\/stage-name":"\([^"]*\)".*/\1/p' <<<"$line")"
  msg="$(sed -n 's/.*"reason":"CustomAuditEvent","message":"\([^"]*\)".*/\1/p' <<<"$line")"
  data="$(grep -o '"ee.kargo.akuity.io/audit-event-data":"{[^}]*}' <<<"$line" | head -1 | sed 's/^[^:]*:"//; s/\\"/"/g')"
  printf '%-21s %-8s %-9s %-8s %s\n' "${when%Z}" "$who" "$what" "$stage" "$msg"
  [[ -z "$data" ]] || printf '%49s%s\n' "" "$data"
done <<<"$events"
