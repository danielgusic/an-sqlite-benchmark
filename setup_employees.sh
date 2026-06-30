#!/usr/bin/env bash
# ONE-TIME setup for the secondary "employees" benchmark: pulls the REAL
# MySQL `employees` sample db (https://github.com/datacharmer/test_db,
# pinned commit below) and loads it into SQLite verbatim. Reuses the cwasm
# binaries built by ./setup.sh -- run that first.
#
# This is a narrow, realistic OLTP HR schema (6 tables, ~3M rows total,
# point-lookup + join heavy) -- the opposite shape from bench.db's bulk
# aggregate workload. See README "Why generate own benchmark db?" for why
# it's a secondary sanity-check benchmark, not the primary one.
#
#   ./setup_employees.sh
#
# Produces, in bench/:
#   .cache/test_db/      - cloned upstream repo (schema + data dumps)
#   bench_employees.db   - the real employees dataset, loaded as-is (AN-off)
set -euo pipefail

REPO_URL="https://github.com/datacharmer/test_db.git"
PINNED_COMMIT="e324b56193ca506ab7cc1ab143a9153d8c4535d7"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WT="$ROOT/wasmtime-an/target/debug/wasmtime"
OFF="$HERE/sqlite.off.cwasm"
DB="$HERE/bench_employees.db"
CACHE="$HERE/.cache/test_db"
GUEST=/w

[[ -f "$OFF" ]] || { echo "missing $OFF -- run ./setup.sh first"; exit 1; }

if [[ ! -d "$CACHE" ]]; then
  echo "==> cloning datacharmer/test_db (pinned @ ${PINNED_COMMIT:0:12})"
  git clone --quiet "$REPO_URL" "$CACHE"
  git -C "$CACHE" checkout --quiet "$PINNED_COMMIT"
else
  got="$(git -C "$CACHE" rev-parse HEAD)"
  [[ "$got" == "$PINNED_COMMIT" ]] || { echo "warning: $CACHE is at $got, expected $PINNED_COMMIT"; }
fi

echo "==> loading real employees dataset into bench_employees.db (AN-off)"
rm -f "$DB"
cat "$HERE/schema_employees.sql" \
    "$CACHE/load_departments.dump" \
    "$CACHE/load_employees.dump" \
    "$CACHE/load_dept_emp.dump" \
    "$CACHE/load_dept_manager.dump" \
    "$CACHE/load_titles.dump" \
    "$CACHE/load_salaries1.dump" \
    "$CACHE/load_salaries2.dump" \
    "$CACHE/load_salaries3.dump" \
  | "$WT" run --dir "$HERE::$GUEST" --allow-precompiled -C cache=n "$OFF" "$GUEST/bench_employees.db" \
    2> >(grep -v sqliterc >&2) | grep -v sqliterc || true

printf "    bench_employees.db: %s MB\n" "$(( $(stat -c %s "$DB") / 1048576 ))"
echo "==> setup done. Now run ./run_employees.sh to benchmark."
