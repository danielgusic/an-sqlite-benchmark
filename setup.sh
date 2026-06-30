#!/usr/bin/env bash
# ONE-TIME setup for the AN-encoding SQLite benchmark. Run this once (or again
# only when you change N, the .wasm, or gen.sql). It does NOT time anything.
#
#   ./setup.sh [N_ROWS]      (default 1,000,000)
#
# Produces, in bench/:
#   sqlite.off.cwasm  - native precompile, AN-encoding OFF
#   sqlite.an.cwasm   - native precompile, AN-encoding ON
#   bench.db          - integer dataset with N rows (built once, AN-off)
set -euo pipefail

N="${1:-1000000}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WT="$ROOT/wasmtime-an/target/debug/wasmtime"
WASM="$ROOT/an-able-sqlite/sqlite.wasm"
OFF="$HERE/sqlite.off.cwasm"
AN="$HERE/sqlite.an.cwasm"
DB="$HERE/bench.db"
GUEST=/w

echo "==> precompile native .cwasm (AN off + AN on)"
"$WT" compile -C an-encoding=n -C cache=n "$WASM" -o "$OFF"
"$WT" compile -C an-encoding=y -C cache=n "$WASM" -o "$AN"
printf "    off: %s MB   an: %s MB\n" \
  "$(( $(stat -c %s "$OFF") / 1048576 ))" "$(( $(stat -c %s "$AN") / 1048576 ))"

echo "==> build bench.db with N=$N integer rows (AN-off)"
rm -f "$DB"
sed "s/__N__/$N/g" "$HERE/gen.sql" \
  | "$WT" run --dir "$HERE::$GUEST" --allow-precompiled -C cache=n "$OFF" "$GUEST/bench.db" \
  2> >(grep -v sqliterc >&2) | grep -v sqliterc || true
echo "$N" > "$HERE/.builtN"
printf "    bench.db: %s MB  (N=%s)\n" "$(( $(stat -c %s "$DB") / 1048576 ))" "$N"
echo "==> setup done. Now run ./run.sh to benchmark."
