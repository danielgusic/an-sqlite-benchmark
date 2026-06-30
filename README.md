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

## Results

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
