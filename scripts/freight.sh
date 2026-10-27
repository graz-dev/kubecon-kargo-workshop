#!/usr/bin/env bash
# Lists the Freight of the project with what the plain `kargo get freight` does not show: the image version and where each
# piece is now. Read-only. Use it to find the alias of a version, for example the one to roll back to.
#
#   scripts/freight.sh
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools
kargo_login

# One line per piece of Freight: alias, image tag, the Stages it is in now, the Stages it was verified in
# shellcheck disable=SC2016 # a Go template, not a shell expression
template='{{range .items}}{{.alias}} {{with .images}}{{(index . 0).tag}}{{end}} |{{range $k, $v := .status.currentlyIn}} {{$k}}{{end}} |{{range $k, $v := .status.verifiedIn}} {{$k}}{{end}}{{"\n"}}{{end}}'
out="$(kargo_cli get freight --project "$KARGO_PROJECT" -o go-template="$template")"
[[ -n "$out" ]] || die "No Freight yet. Run: make release VERSION=1.0.0"
printf '%s\n' "$out" | sort -t' ' -k2 -V | awk -F'|' '
  BEGIN { printf "%-22s %-9s %-56s %s\n", "ALIAS", "VERSION", "IN NOW", "VERIFIED IN" }
  { split($1, a, " "); gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3)
    printf "%-22s %-9s %-56s %s\n", a[1], a[2], ($2 == "" ? "-" : $2), ($3 == "" ? "-" : $3) }'
