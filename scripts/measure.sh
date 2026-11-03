#!/usr/bin/env bash
# What the workshop environment uses on this machine: memory, CPU and disk. Read-only. For the maintainers: it is how the
# requirements in the README and the thresholds of `make doctor` were measured. Run it with the cluster up and the labs done.
#
#   scripts/measure.sh              a snapshot
#   scripts/measure.sh watch 120    also samples the cluster for 120 seconds: start it, then run a heavy step in another terminal
#                                   (for example `kargo promote --project guestbook --stage dev --warehouse app` after Lab 11)
#
# The time of `make up` is not measured here: run `time make up` on a machine that has never run it.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_docker

NODE="${CLUSTER_NAME}-control-plane"
docker inspect "$NODE" >/dev/null 2>&1 || die "The cluster '$CLUSTER_NAME' is not running. Run: make up"

WATCH_SECONDS=0
if [[ "${1:-}" == watch ]]; then
  WATCH_SECONDS="${2:-60}"
fi

# Converts "2.935GiB", "512MiB", "38.06MB" and "495.6kB" to MiB or MB-ish megabytes: prints a number of megabytes
to_mb() {
  awk '{
    v = $0; u = v; sub(/^[0-9.]+/, "", u); sub(/[^0-9.].*$/, "", v)
    if (u == "GiB") m = v * 1024; else if (u == "MiB") m = v; else if (u == "KiB") m = v / 1024
    else if (u == "GB") m = v * 1000; else if (u == "MB") m = v; else if (u == "kB") m = v / 1000; else m = v / 1000000
    printf "%.0f\n", m
  }'
}

section() { printf '\n%s%s%s\n' "$_C_BLUE" "$1" "$_C_RESET"; }

section "Docker"
docker info --format '{{.OperatingSystem}}|{{.ServerVersion}}|{{.NCPU}}|{{.MemTotal}}' 2>/dev/null |
  awk -F'|' '{printf "  engine: %s, server %s, %d CPUs, %.1f GiB for Docker\n", $1, $2, $3, $4 / 1073741824}'

section "The cluster node, now"
docker stats --no-stream --format '  memory {{.MemUsage}} ({{.MemPerc}} of the Docker memory), CPU {{.CPUPerc}} (100% is one core)' "$NODE"
printf '  pods: %s\n' "$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"

section "Memory of the containers inside the node (top 8)"
docker exec "$NODE" crictl stats 2>/dev/null | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' |
  awk 'NR > 1 {print $4, $2}' | while read -r mem name; do
  printf '%s %s\n' "$(printf '%s' "$mem" | to_mb)" "$name"
done | sort -rn | awk '{t += $1; if (NR <= 8) printf "  %6d MB  %s\n", $1, $2} END {printf "  %6d MB  all %d containers\n", t, NR}'

section "Disk"
docker exec "$NODE" crictl images 2>/dev/null | awk 'NR > 1 {print $4}' | while read -r size; do
  printf '%s\n' "$size" | to_mb
done | awk '{t += $1; n++} END {printf "  images in the node: %d, %.2f GB\n", n, t / 1000}'
volume="$(docker inspect "$NODE" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}')"
if [[ -n "$volume" ]]; then
  printf '  data of the node (a Docker volume): %s\n' "$(docker system df -v 2>/dev/null | awk -v v="$volume" '$1 == v {print $NF}')"
fi
docker system df | sed 's/^/  /'
printf '  .tools (the pinned CLIs): %s\n' "$(du -sh "$TOOLS_DIR" 2>/dev/null | cut -f1)"

if ((WATCH_SECONDS > 0)); then
  section "Sampling the node for ${WATCH_SECONDS}s (every second)"
  end=$((SECONDS + WATCH_SECONDS))
  samples="$(mktemp)"
  trap 'rm -f "$samples"' EXIT
  while ((SECONDS < end)); do
    docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$NODE" | awk '{print $1, $2}' >>"$samples"
    sleep 1
  done
  while read -r cpu mem; do
    printf '%s %s\n' "${cpu%\%}" "$(printf '%s' "$mem" | to_mb)"
  done <"$samples" | awk '
    NR == 1 {cmin = cmax = $1; mmin = mmax = $2}
    {c += $1; m += $2; if ($1 < cmin) cmin = $1; if ($1 > cmax) cmax = $1; if ($2 < mmin) mmin = $2; if ($2 > mmax) mmax = $2}
    END {printf "  %d samples\n  memory MiB: min %d, average %d, max %d\n  CPU %%: min %d, average %d, max %d (100 is one core)\n", NR, mmin, m / NR, mmax, cmin, c / NR, cmax}'
fi
printf '\n'
