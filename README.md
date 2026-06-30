# AN-Encoding SQLite Benchmark

**Note:** This was created with the help of AI.

## Setup

| Parameter | Value |
|-----------|-------|
| Dataset | `bench.db` — 40 MB, N=1,000,000 rows |
| Repetitions | 5 per configuration |
| Runtime | `wasmtime-an` (custom Wasmtime with AN-encoding support) |

## Workloads

Two independent workloads exercise different integer widths:

**i32 workload** (queries R1–R7, writes W1–W6)
- Full-table aggregates, filtered scans, group-by, sorts, joins, text sort
- Bulk insert (~20% new rows), large UPDATE, DELETE, index creation, VACUUM

**i64 workload** (queries R8–R12, writes W1v–W6)
- Full-table aggregate, selective filter, range group-by, full sort, distinct cardinality on the 64-bit `v` column
- Bulk insert (~20% new rows), large UPDATE, DELETE, index creation on `v`, indexed range read, VACUUM

Each rep copies `bench.db` to a fresh writable file so writes are always applied to identical starting data.


## Benchmark DBs
- **Synthetic (`bench.db`)** — generated rather than reused, because the SQLite build here is compiled with `-DSQLITE_OMIT_FLOATING_POINT`, which disqualifies most standard SQL benchmarks outright (TPC-H/DS/C, SSB, Northwind, Chinook, NYC Taxi are all decimal/float-heavy by spec). Generating our own data gave precise control over column types (pure i32- and i64-range `INTEGER` columns, no floats anywhere) and let us build a write-heavy aggregate workload dense enough in integer arithmetic to make AN-encoding overhead clearly measurable. 
- **MySQL `employees`** — the real [sample db](https://github.com/datacharmer/test_db). `salary` is `INT` with no floating-point columns anywhere, so it loads natively under the OMIT_FLOATING_POINT build with no schema changes. It's a narrow **OLTP** HR schema (point lookups + joins on employee/department/date, not bulk aggregation).

## Results

### Sqlite binary size

- AN-off: ~5 MB
- AN-on: ~50 MB

### i32 Workload

| Mode | Avg | Min | Max | Peak RSS (avg) |
|------|-----|-----|-----|----------------|
| AN-off | 33.47 s | 30.07 s | 36.55 s | 133,526 KB |
| AN-on  | 154.10 s | 150.42 s | 158.92 s | 416,981 KB |

**Slowdown: 4.60x** — runtime; **3.12x** — memory

### i64 Workload

| Mode | Avg | Min | Max | Peak RSS (avg) |
|------|-----|-----|-----|----------------|
| AN-off | 21.14 s | 18.03 s | 28.21 s | 140,642 KB |
| AN-on  | 124.28 s | 117.46 s | 144.24 s | 452,525 KB |

**Slowdown: 5.88x** — runtime; **3.22x** — memory

### Correctness

Output between AN-off and AN-on is **byte-identical** for both workloads, confirming that AN-encoding is transparent to query results.

## Employees benchmark

In addition to the synthetic primary benchmark, `setup_employees.sh` / `run_employees.sh` pull and run the actual MySQL [`employees` sample db](https://github.com/datacharmer/test_db) (pinned commit `e324b56193`) — 6 tables, ~3M rows, ~240 MB loaded. The schema is a 1:1 type translation into SQLite (`DATE`/`VARCHAR`/`ENUM` → `TEXT`, `INT` → `INTEGER`); no row data is altered. `workload_employees.sql` runs realistic OLTP queries against it: point lookups by `emp_no`, current-department/title/salary joins, per-department aggregates, an onboarding/raise/promotion/termination write sequence, an index build, and `VACUUM`.

| Mode | Avg | Min | Max | Peak RSS (avg) |
|------|-----|-----|-----|----------------|
| AN-off | 36.63 s | 36.63 s | 36.63 s | 321,436 KB |
| AN-on  | 656.18 s | 656.18 s | 656.18 s | 1,359,760 KB |

**Slowdown: 17.91x** (1 rep — re-run with more reps for stable min/max). Output is **byte-identical** between modes.

## Reproducing

### Prerequisites

- A recent Rust toolchain (for building `wasmtime-an`)
- Clone these three repos side by side:

```sh
git clone https://github.com/danielgusic/wasmtime-an
git clone https://github.com/danielgusic/an-able-sqlite
git clone https://github.com/danielgusic/an-sqlite-bench
# parent/
# ├── wasmtime-an        (AN-encoding Wasmtime fork)
# ├── an-able-sqlite     (float-free SQLite WASI module)
# └── an-sqlite-bench    (this repo)
```

Build the runtime:

```sh
cd wasmtime-an && cargo build -p wasmtime-cli
```

### Running

```bash
cd an-sqlite-bench

# Precompile .cwasm artifacts and generate bench.db (run once)
./setup.sh

# Precompile and generate with a custom row count
./setup.sh 10000000

# Run the benchmark (default 5 reps)
./run.sh

# Run with a custom rep count
./run.sh 10
```

### Running the secondary (real `employees`) benchmark

Requires network access to clone `datacharmer/test_db` on first run.

```bash
# Clone the real employees dataset and load it into bench_employees.db (run once)
./setup_employees.sh

# Run the benchmark (default 5 reps)
./run_employees.sh

# Run with a custom rep count
./run_employees.sh 10
```
