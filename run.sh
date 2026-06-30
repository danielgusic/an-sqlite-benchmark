#!/usr/bin/env bash
# AN-encoding SQLite benchmark: read+write workload, AN-off vs AN-on.
# Assumes ./setup.sh has already produced sqlite.off.cwasm, sqlite.an.cwasm and
# bench.db. This script ONLY runs the timed workload (no compiling, no DB build).
#
#   ./run.sh [REPS]          (default 5)
#
# Runs two independent workloads (i32 and i64) against both modes. Each rep
# copies bench.db to a fresh writable file. Reports avg/min/max wall time and
# peak RSS per workload per mode, plus the AN-on/AN-off slowdown ratio for each.
set -euo pipefail

REPS="${1:-5}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WT="$ROOT/wasmtime-an/target/debug/wasmtime"
OFF="$HERE/sqlite.off.cwasm"
AN="$HERE/sqlite.an.cwasm"
DB="$HERE/bench.db"
WL_I32="$HERE/workload_i32.sql"
WL_I64="$HERE/workload_i64.sql"
GUEST=/w

for f in "$OFF" "$AN" "$DB" "$WL_I32" "$WL_I64"; do
  [[ -f "$f" ]] || { echo "missing $f -- run ./setup.sh first"; exit 1; }
done
echo "dataset: bench.db = $(( $(stat -c %s "$DB") / 1048576 )) MB (N=$(cat "$HERE/.builtN" 2>/dev/null)), reps=$REPS"

# run_once <label> <cwasm> <workload_sql> <extra wasmtime flags...>
# prints "<wall_s> <peakRSS_kb>"
run_once() {
  local label="$1" cw="$2" wl="$3"; shift 3
  cp "$DB" "$HERE/work_$label.db"
  local tf="$HERE/.time_$label"
  /usr/bin/time -o "$tf" -f "%e %M" \
    "$WT" run --dir "$HERE::$GUEST" --allow-precompiled -C cache=n "$@" "$cw" "$GUEST/work_$label.db" \
    < "$wl" > "$HERE/out_$label.txt" 2> >(grep -v sqliterc >&2)
  rm -f "$HERE/work_$label.db"
  cat "$tf"; rm -f "$tf"
}

# stats over a list of numbers: prints "avg min max"
stats() { printf '%s\n' "$@" | awk '
  NR==1{min=max=$1} {s+=$1; n++; if($1<min)min=$1; if($1>max)max=$1}
  END{printf "%.2f %.2f %.2f", s/n, min, max}'; }

declare -a off_i32_t off_i32_m an_i32_t an_i32_m
declare -a off_i64_t off_i64_m an_i64_t an_i64_m

# ---- i32 workload -----------------------------------------------------------

echo "==> i32 workload / AN-OFF: $REPS reps"
for ((i=1;i<=REPS;i++)); do
  read -r w m < <(run_once off_i32 "$OFF" "$WL_I32")
  off_i32_t[i]=$w; off_i32_m[i]=$m
  printf "    rep %d/%d: wall=%ss  peakRSS=%sKB\n" "$i" "$REPS" "$w" "$m"
done

echo "==> i32 workload / AN-ON: $REPS reps"
for ((i=1;i<=REPS;i++)); do
  read -r w m < <(run_once an_i32 "$AN" "$WL_I32" -C an-encoding=y)
  an_i32_t[i]=$w; an_i32_m[i]=$m
  printf "    rep %d/%d: wall=%ss  peakRSS=%sKB\n" "$i" "$REPS" "$w" "$m"
done

# ---- i64 workload -----------------------------------------------------------

echo "==> i64 workload / AN-OFF: $REPS reps"
for ((i=1;i<=REPS;i++)); do
  read -r w m < <(run_once off_i64 "$OFF" "$WL_I64")
  off_i64_t[i]=$w; off_i64_m[i]=$m
  printf "    rep %d/%d: wall=%ss  peakRSS=%sKB\n" "$i" "$REPS" "$w" "$m"
done

echo "==> i64 workload / AN-ON: $REPS reps"
for ((i=1;i<=REPS;i++)); do
  read -r w m < <(run_once an_i64 "$AN" "$WL_I64" -C an-encoding=y)
  an_i64_t[i]=$w; an_i64_m[i]=$m
  printf "    rep %d/%d: wall=%ss  peakRSS=%sKB\n" "$i" "$REPS" "$w" "$m"
done

# ---- results ----------------------------------------------------------------

read -r off_i32_avg off_i32_min off_i32_max <<<"$(stats "${off_i32_t[@]}")"
read -r an_i32_avg  an_i32_min  an_i32_max  <<<"$(stats "${an_i32_t[@]}")"
read -r off_i64_avg off_i64_min off_i64_max <<<"$(stats "${off_i64_t[@]}")"
read -r an_i64_avg  an_i64_min  an_i64_max  <<<"$(stats "${an_i64_t[@]}")"

read -r off_i32_mavg _ _ <<<"$(stats "${off_i32_m[@]}")"; off_i32_mavg=$(printf '%.0f' "$off_i32_mavg")
read -r an_i32_mavg  _ _ <<<"$(stats "${an_i32_m[@]}")";  an_i32_mavg=$(printf '%.0f' "$an_i32_mavg")
read -r off_i64_mavg _ _ <<<"$(stats "${off_i64_m[@]}")"; off_i64_mavg=$(printf '%.0f' "$off_i64_mavg")
read -r an_i64_mavg  _ _ <<<"$(stats "${an_i64_m[@]}")";  an_i64_mavg=$(printf '%.0f' "$an_i64_mavg")

ratio_i32="$(awk -v a="$an_i32_avg" -v o="$off_i32_avg" 'BEGIN{printf "%.2f", a/o}')"
ratio_i64="$(awk -v a="$an_i64_avg" -v o="$off_i64_avg" 'BEGIN{printf "%.2f", a/o}')"

echo
echo "================= RESULTS (avg of $REPS reps) ================="
echo "  -- i32 workload (R1-R7, W1-W6) --"
printf "  %-7s  avg=%6ss   min=%6ss   max=%6ss   peakRSS(avg)=%sKB\n" \
  "AN-off" "$off_i32_avg" "$off_i32_min" "$off_i32_max" "$off_i32_mavg"
printf "  %-7s  avg=%6ss   min=%6ss   max=%6ss   peakRSS(avg)=%sKB\n" \
  "AN-on"  "$an_i32_avg"  "$an_i32_min"  "$an_i32_max"  "$an_i32_mavg"
printf "  AN-on / AN-off slowdown = %sx\n" "$ratio_i32"
echo
echo "  -- i64 workload (R8-R9, Wv) --"
printf "  %-7s  avg=%6ss   min=%6ss   max=%6ss   peakRSS(avg)=%sKB\n" \
  "AN-off" "$off_i64_avg" "$off_i64_min" "$off_i64_max" "$off_i64_mavg"
printf "  %-7s  avg=%6ss   min=%6ss   max=%6ss   peakRSS(avg)=%sKB\n" \
  "AN-on"  "$an_i64_avg"  "$an_i64_min"  "$an_i64_max"  "$an_i64_mavg"
printf "  AN-on / AN-off slowdown = %sx\n" "$ratio_i64"
echo "=============================================================="

echo "--- output identical between modes? (correctness check) ---"
for wl in i32 i64; do
  if diff -q "$HERE/out_off_$wl.txt" "$HERE/out_an_$wl.txt" >/dev/null 2>&1; then
    echo "    $wl: YES - byte-identical"
  else
    echo "    $wl: NO - differences:"; diff "$HERE/out_off_$wl.txt" "$HERE/out_an_$wl.txt" | head
  fi
done
