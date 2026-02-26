# concore-jl Benchmark Suite

Comprehensive performance benchmarks for the concore-jl Julia package, demonstrating Julia's performance advantages for closed-loop peripheral neuromodulation control systems.

## Quick Start

```bash
# Full benchmark suite (Julia only)
julia benchmark/run_benchmarks.jl

# Full suite + Python comparison
julia benchmark/run_benchmarks.jl --with-python

# Quick mode (skip multi-process, faster)
julia benchmark/run_benchmarks.jl --quick

# Quick mode + Python comparison
julia benchmark/run_benchmarks.jl --quick --with-python
```

## Individual Benchmarks

Each benchmark file can be run standalone:

```bash
julia benchmark/bench_parser.jl       # Wire format parser throughput
julia benchmark/bench_io.jl           # File I/O throughput
julia benchmark/bench_loop.jl         # Full control loop simulation
julia benchmark/bench_shm.jl          # Shared memory backend
julia benchmark/bench_memory.jl       # Memory allocation analysis
julia benchmark/bench_latency.jl      # Latency distribution & tail latency
julia benchmark/bench_multiprocess.jl # Multi-process IPC

python3 benchmark/bench_python_compare.py  # Python equivalents
```

## Benchmark Categories

### 1. Parser (`bench_parser.jl`)

Measures wire-format parsing throughput -- the CPU-intensive hot path in concore.

- **`safe_parse_list`**: Regex-based parsing for small (2 elem), medium (10 elem), and large (101 elem) inputs
- **Numpy wrapper handling**: `np.float64(...)` unwrapping
- **`_format_wire`**: Reverse direction (Vector{Float64} to wire string)

**Why it matters:** Parsing runs on every read. Julia's compiled regex + type-stable Float64 parsing avoids Python's interpreter overhead entirely.

### 2. File I/O (`bench_io.jl`)

Measures file-based IPC throughput -- the filesystem-bound path.

- **Single write+read cycle**: format + write + read + parse
- **100-cycle control loop**: Sustained throughput
- **Write throughput**: ops/sec for file writes
- **Read+parse throughput**: ops/sec for file reads + parsing

**Why it matters:** File I/O is kernel-bound (both languages call the same syscalls), but Julia avoids Python's per-call interpreter overhead.

### 3. Control Loop (`bench_loop.jl`)

Full closed-loop simulation: controller + plant model communicating through files.

- **1000-iteration loop**: Proportional controller (`u = -K * ym`) + first-order plant (`ym = A*ym + B*u`)
- **Per-iteration latency**: The real-world metric for control loop timing
- **Loop rate**: How many control iterations per second
- **Convergence verification**: Confirms the controller drives ym toward 0

**Why it matters:** This is the complete hot path for neuromodulation. Every microsecond of per-iteration latency matters.

### 4. Shared Memory (`bench_shm.jl`)

Benchmarks Julia's `Mmap.jl`-based shared memory backend vs file I/O.

- **SHM write+read cycle latency**: Mmap-backed vs file-backed
- **SHM throughput**: ops/sec comparison
- **SHM control loop**: Full loop using shared memory IPC
- **Backend comparison**: Side-by-side File vs SHM numbers

**Why it matters:** Shared memory avoids filesystem buffering overhead for same-host communication. Python has no built-in equivalent that integrates with the concore wire protocol.

### 5. Memory Allocation (`bench_memory.jl`)

Measures heap allocations per operation using Julia's `@allocated` macro.

- **Parse allocations**: Bytes allocated per parse call
- **Format allocations**: Bytes per format call
- **I/O cycle allocations**: Full write+read cycle
- **SHM vs File allocation comparison**: Which backend allocates less

**Why it matters:** Less allocation = less GC pressure = lower tail latency. Julia can achieve zero-allocation or near-zero-allocation hot paths. Python allocates heap objects for every operation (integers, floats, strings, lists).

### 6. Latency Distribution (`bench_latency.jl`)

Detailed percentile analysis for real-time control applications.

- **Percentiles**: p50, p95, p99, p99.9 for all operations
- **Jitter**: Standard deviation of latencies (scheduling noise)
- **GC impact**: Latency with and without GC pressure
- **Text histogram**: Visual latency distribution

**Why it matters for neuromodulation:** Real-time control systems care about **worst-case** latency, not average. A GC pause at the wrong moment can cause a missed control deadline, potentially affecting patient safety. Julia's generational GC has lower impact than Python's reference-counting + cyclic collection.

### 7. Multi-Process IPC (`bench_multiprocess.jl`)

True multi-process benchmarks with separate Julia worker processes.

- **Single-process baseline**: Message throughput without process overhead
- **Multi-process control loop**: Separate controller + plant processes
- **IPC overhead measurement**: Process scheduling + filesystem coherence cost
- **Single vs multi-process comparison**: Quantifies the IPC tax

**Why it matters:** Real concore deployments run controller and plant in separate OS processes. This benchmark captures the true end-to-end performance including OS scheduling.

## Methodology

- **Zero external dependencies**: Uses `@elapsed` and `@allocated` (no BenchmarkTools.jl)
- **JIT warmup**: All benchmarks warm up before measurement
- **Large sample sizes**: 10K-50K iterations for reliable statistics
- **Temp directories**: All file operations use `mktempdir()` with cleanup
- **Percentile analysis**: Sorted arrays with correct index computation
- **GC measurement**: Controlled GC forcing to measure impact
- **System info**: Reports Julia version, OS, CPU in results

## Output

Results are printed to stdout and saved to `benchmark/results.md` as a comprehensive markdown report with:

- System information header
- Comparison tables (Julia vs Python with speedup ratios)
- Backend comparison (File vs SHM)
- Latency distribution tables with percentiles
- Memory allocation analysis
- Multi-process IPC results
- Summary with implications for neuromodulation

## Expected Results

On typical hardware, expect:

| Category | Julia Advantage |
|:---------|:----------------|
| Parse throughput | 10-100x faster than Python |
| Format throughput | 10-50x faster than Python |
| File I/O | 2-5x faster (kernel-bound bottleneck) |
| Control loop rate | 5-20x faster than Python |
| SHM vs File | 1.5-3x faster (Julia-only capability) |
| Tail latency (p99.9) | Dramatically lower and more predictable |
| Memory allocation | Orders of magnitude less per operation |
| GC impact | Minimal (generational) vs significant (Python) |

The bottleneck in file-based IPC is the kernel (both languages call the same `read(2)`/`write(2)` syscalls), which is why I/O speedups are modest. The massive speedups come from computation (parsing, formatting) where Julia's compiled code eliminates interpreter overhead entirely.

## Interpreting Results for Neuromodulation

For closed-loop peripheral neuromodulation:

1. **Control loop rate > 1000 Hz** is typical requirement. Julia achieves this easily in single-process mode.
2. **Tail latency < 1ms** is critical. Julia's p99.9 latencies are consistently sub-millisecond.
3. **Zero GC pauses** during control. Julia's minimal allocation means the GC rarely triggers during hot paths.
4. **SHM backend** eliminates filesystem overhead for same-host deployments, reducing latency further.

These are not just benchmarks -- they are **requirements** for safe, effective neuromodulation therapy.
