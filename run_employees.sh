#!/usr/bin/env bash
# Secondary "realistic usage" benchmark: AN-off vs AN-on on the real MySQL
# `employees` sample db (narrow OLTP HR schema, point-lookup + join heavy).
# This is NOT the primary AN-encoding overhead measurement (see README's
# "Why generate own benchmark db?") -- it's a sanity check that the encoding
# holds up under a workload shape that looks like real SQLite usage instead
# of an adversarial bulk-aggregate synthetic one.
#
# Assumes ./setup.sh and ./setup_employees.sh have already run.
#
#   ./run_employees.sh [REPS]          (default 5)
set -euo pipefail

REPS="${1:-5}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WT="$ROOT/wasmtime-an/target/debug/wasmtime"
OFF="$HERE/sqlite.off.cwasm"
AN="$HERE/sqlite.an.cwasm"
DB="$HERE/bench_employees.db"
WL="$HERE/workload_employees.sql"
GUEST=/w

for f in "$OFF" "$AN" "$DB" "$WL"; do
  [[ -f "$f" ]] || { echo "missing $f -- run ./setup.sh and ./setup_employees.sh first"; exit 1; }
done
echo "dataset: bench_employees.db = $(( $(stat -c %s "$DB") / 1048576 )) MB, reps=$REPS"

# run_once <label> <cwasm> <extra wasmtime flags...>
# prints "<wall_s> <peakRSS_kb>"
run_once() {
  local label="$1" cw="$2"; shift 2
  cp "$DB" "$HERE/work_$label.db"
  local tf="$HERE/.time_$label"
  /usr/bin/time -o "$tf" -f "%e %M" \
    "$WT" run --dir "$HERE::$GUEST" --allow-precompiled -C cache=n "$@" "$cw" "$GUEST/work_$label.db" \
    < "$WL" > "$HERE/out_$label.txt" 2> >(grep -v sqliterc >&2)
  rm -f "$HERE/work_$label.db"
  cat "$tf"; rm -f "$tf"
}

# stats over a list of numbers: prints "avg min max"
stats() { printf '%s\n' "$@" | awk '
  NR==1{min=max=$1} {s+=$1; n++; if($1<min)min=$1; if($1>max)max=$1}
  END{printf "%.2f %.2f %.2f", s/n, min, max}'; }

declare -a off_t off_m an_t an_m

echo "==> employees workload / AN-OFF: $REPS reps"
for ((i=1;i<=REPS;i++)); do
  read -r w m < <(run_once off_employees "$OFF")
  off_t[i]=$w; off_m[i]=$m
  printf "    rep %d/%d: wall=%ss  peakRSS=%sKB\n" "$i" "$REPS" "$w" "$m"
done

echo "==> employees workload / AN-ON: $REPS reps"
for ((i=1;i<=REPS;i++)); do
  read -r w m < <(run_once an_employees "$AN" -C an-encoding=y)
  an_t[i]=$w; an_m[i]=$m
  printf "    rep %d/%d: wall=%ss  peakRSS=%sKB\n" "$i" "$REPS" "$w" "$m"
done

read -r off_avg off_min off_max <<<"$(stats "${off_t[@]}")"
read -r an_avg  an_min  an_max  <<<"$(stats "${an_t[@]}")"
read -r off_mavg _ _ <<<"$(stats "${off_m[@]}")"; off_mavg=$(printf '%.0f' "$off_mavg")
read -r an_mavg  _ _ <<<"$(stats "${an_m[@]}")";  an_mavg=$(printf '%.0f' "$an_mavg")
ratio="$(awk -v a="$an_avg" -v o="$off_avg" 'BEGIN{printf "%.2f", a/o}')"

echo
echo "================= RESULTS (avg of $REPS reps) ================="
printf "  %-7s  avg=%6ss   min=%6ss   max=%6ss   peakRSS(avg)=%sKB\n" \
  "AN-off" "$off_avg" "$off_min" "$off_max" "$off_mavg"
printf "  %-7s  avg=%6ss   min=%6ss   max=%6ss   peakRSS(avg)=%sKB\n" \
  "AN-on"  "$an_avg"  "$an_min"  "$an_max"  "$an_mavg"
printf "  AN-on / AN-off slowdown = %sx\n" "$ratio"
echo "=============================================================="

echo "--- output identical between modes? (correctness check) ---"
if diff -q "$HERE/out_off_employees.txt" "$HERE/out_an_employees.txt" >/dev/null 2>&1; then
  echo "    YES - byte-identical"
else
  echo "    NO - differences:"; diff "$HERE/out_off_employees.txt" "$HERE/out_an_employees.txt" | head
fi
