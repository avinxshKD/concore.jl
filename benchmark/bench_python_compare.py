#!/usr/bin/env python3
"""
bench_python_compare.py -- Python equivalent benchmarks for concore comparison.

Mirrors the Julia benchmarks so we can directly compare:
  - Wire-format parsing (regex-based, same approach as Julia)
  - File I/O throughput
  - Full control loop simulation
  - Latency distributions (p50, p95, p99, p99.9)
  - Memory/allocation overhead (via tracemalloc)

Categories where Python CANNOT compete (marked N/A):
  - Shared memory IPC (no built-in mmap + wire format integration)
  - Zero-allocation hot paths (CPython allocates on every operation)

Usage:
    python3 benchmark/bench_python_compare.py
"""

import gc
import json
import math
import os
import re
import shutil
import sys
import tempfile
import time

try:
    import tracemalloc

    HAS_TRACEMALLOC = True
except ImportError:
    HAS_TRACEMALLOC = False


# ─── Helpers ─────────────────────────────────────────────────────────────────


def bench(f, n):
    """Run f() for n iterations, return (min, mean, median) in seconds."""
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        f()
        times.append(time.perf_counter() - t0)
    times.sort()
    return {
        "min": times[0],
        "mean": sum(times) / n,
        "median": times[n // 2],
    }


def latency_distribution(f, n):
    """Collect n latency samples, return full distribution analysis."""
    # Warmup
    for _ in range(min(100, n // 10)):
        f()

    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        f()
        times.append(time.perf_counter() - t0)

    times.sort()
    mn = times[0]
    mx = times[-1]
    avg = sum(times) / n
    med = times[n // 2]
    p50 = times[max(0, math.ceil(0.50 * n) - 1)]
    p95 = times[max(0, math.ceil(0.95 * n) - 1)]
    p99 = times[max(0, math.ceil(0.99 * n) - 1)]
    p999 = times[max(0, math.ceil(0.999 * n) - 1)]
    stddev = (sum((t - avg) ** 2 for t in times) / n) ** 0.5

    return {
        "min": mn,
        "max": mx,
        "mean": avg,
        "median": med,
        "p50": p50,
        "p95": p95,
        "p99": p99,
        "p999": p999,
        "stddev": stddev,
    }


def measure_peak_memory(f, n=100):
    """Measure peak memory usage of f() over n calls using tracemalloc."""
    if not HAS_TRACEMALLOC:
        return {"peak_bytes": "N/A", "per_call_bytes": "N/A"}

    # Warmup
    for _ in range(10):
        f()

    gc.collect()
    tracemalloc.start()
    snapshot_before = tracemalloc.take_snapshot()

    for _ in range(n):
        f()

    snapshot_after = tracemalloc.take_snapshot()
    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()

    return {
        "peak_bytes": peak,
        "per_call_bytes": peak / n if n > 0 else 0,
    }


# ─── Parser equivalent ──────────────────────────────────────────────────────


def safe_parse_list_python(s):
    """Parse concore wire format using regex + float(), mimicking Julia version."""
    cleaned = s.strip()
    # Strip numpy wrappers
    cleaned = re.sub(r"(?:np|numpy)\.\w+\(([^()]+)\)", r"\1", cleaned)
    cleaned = re.sub(r"(?:np|numpy)\.array\(", "", cleaned)
    cleaned = re.sub(r"\)$", "", cleaned)
    cleaned = cleaned.strip()
    # Python booleans
    cleaned = re.sub(r"\bTrue\b", "1.0", cleaned)
    cleaned = re.sub(r"\bFalse\b", "0.0", cleaned)
    cleaned = re.sub(r"\bNone\b", "0.0", cleaned)
    # Strip brackets
    inner = cleaned.strip("[]")
    parts = inner.split(",")
    return [float(p.strip()) for p in parts]


def format_wire_python(vals):
    """Format list as concore wire string, matching Julia _format_wire."""
    parts = []
    for v in vals:
        if v == int(v) and abs(v) < 1e15:
            parts.append(f"{int(v)}.0")
        else:
            parts.append(str(v))
    return "[" + ", ".join(parts) + "]"


# ─── Test inputs ─────────────────────────────────────────────────────────────

SMALL_INPUT = "[0.0, 1.0]"
MEDIUM_INPUT = "[0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]"
LARGE_INPUT = "[0.0, " + ", ".join(f"{i}.0" for i in range(1, 101)) + "]"
NUMPY_INPUT = "[np.float64(0.0), np.float64(1.0)]"

FORMAT_SMALL = [0.0, 1.0]
FORMAT_MEDIUM = list(range(10))
FORMAT_LARGE = [0.0] + list(range(1, 101))

N_ITERS = 10_000


# ─── Parser benchmarks ──────────────────────────────────────────────────────


def run_parser_benchmarks():
    results = {}

    print(f"Parser Benchmarks ({N_ITERS} iterations each)")
    print("=" * 70)

    r = bench(lambda: safe_parse_list_python(SMALL_INPUT), N_ITERS)
    results["parse_small"] = r
    print(
        f"  parse small  (2 elem)   : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: safe_parse_list_python(MEDIUM_INPUT), N_ITERS)
    results["parse_medium"] = r
    print(
        f"  parse medium (10 elem)  : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: safe_parse_list_python(LARGE_INPUT), N_ITERS)
    results["parse_large"] = r
    print(
        f"  parse large  (101 elem) : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: safe_parse_list_python(NUMPY_INPUT), N_ITERS)
    results["parse_numpy"] = r
    print(
        f"  parse numpy wrappers    : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: format_wire_python(FORMAT_SMALL), N_ITERS)
    results["format_small"] = r
    print(
        f"  format small (2 elem)   : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: format_wire_python(FORMAT_MEDIUM), N_ITERS)
    results["format_medium"] = r
    print(
        f"  format medium (10 elem) : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: format_wire_python(FORMAT_LARGE), N_ITERS)
    results["format_large"] = r
    print(
        f"  format large (101 elem) : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    print()
    return results


# ─── I/O benchmarks ─────────────────────────────────────────────────────────

N_SINGLE = 1_000
N_CYCLE = 100
N_THROUGHPUT = 10_000


def run_io_benchmarks():
    results = {}
    tmpdir = tempfile.mkdtemp()
    outd = os.path.join(tmpdir, "out1")
    ind = os.path.join(tmpdir, "in1")
    os.makedirs(outd, exist_ok=True)
    os.makedirs(ind, exist_ok=True)

    print("File I/O Benchmarks")
    print("=" * 70)

    def single_write_read():
        val = [0.0, 42.0, 3.14]
        wire = format_wire_python(val)
        outpath = os.path.join(outd, "signal")
        with open(outpath, "w") as f:
            f.write(wire)
        inpath = os.path.join(ind, "signal")
        shutil.copy2(outpath, inpath)
        with open(inpath, "r") as f:
            raw = f.read()
        return safe_parse_list_python(raw)

    # Warmup
    single_write_read()

    r = bench(single_write_read, N_SINGLE)
    results["single_write_read"] = r
    print(
        f"  single write+read       : min={r['min'] * 1e6:.2f}μs  median={r['median'] * 1e6:.2f}μs"
    )

    r = bench(lambda: [single_write_read() for _ in range(N_CYCLE)], N_SINGLE)
    results["100_cycle"] = r
    per_iter = r["median"] / N_CYCLE
    print(
        f"  100-cycle loop          : median={r['median'] * 1e3:.2f}ms  ({per_iter * 1e6:.2f}μs/iter)"
    )

    # Write throughput
    val = [0.0, 1.0, 2.0, 3.0, 4.0]
    wire = format_wire_python(val)
    filepath = os.path.join(outd, "signal")
    t0 = time.perf_counter()
    for _ in range(N_THROUGHPUT):
        with open(filepath, "w") as f:
            f.write(wire)
    wt = time.perf_counter() - t0
    wps = N_THROUGHPUT / wt
    results["write_throughput_ops_sec"] = wps
    print(
        f"  write throughput        : {wps:.0f} writes/sec  ({N_THROUGHPUT} ops in {wt * 1e3:.1f}ms)"
    )

    # Read throughput
    filepath = os.path.join(ind, "signal")
    wire = format_wire_python([0.0, 1.0, 2.0, 3.0, 4.0])
    with open(filepath, "w") as f:
        f.write(wire)
    t0 = time.perf_counter()
    for _ in range(N_THROUGHPUT):
        with open(filepath, "r") as f:
            raw = f.read()
        safe_parse_list_python(raw)
    rt = time.perf_counter() - t0
    rps = N_THROUGHPUT / rt
    results["read_throughput_ops_sec"] = rps
    print(
        f"  read+parse throughput   : {rps:.0f} reads/sec  ({N_THROUGHPUT} ops in {rt * 1e3:.1f}ms)"
    )

    print()
    shutil.rmtree(tmpdir, ignore_errors=True)
    return results


# ─── Control loop benchmark ─────────────────────────────────────────────────

N_LOOP_ITERS = 1000
N_REPEATS = 10


def simulate_control_loop(n_iters):
    tmpdir = tempfile.mkdtemp()
    ctrl_out = os.path.join(tmpdir, "ctrl_out")
    pm_out = os.path.join(tmpdir, "pm_out")
    os.makedirs(ctrl_out, exist_ok=True)
    os.makedirs(pm_out, exist_ok=True)

    K = 0.5
    A = 0.9
    B = 0.1
    simtime = 0.0
    ym = [1.0]

    u_path = os.path.join(ctrl_out, "u")
    ym_path = os.path.join(pm_out, "ym")

    for _ in range(n_iters):
        # Controller reads ym
        ym_wire = format_wire_python([simtime] + ym)
        with open(ym_path, "w") as f:
            f.write(ym_wire)
        with open(ym_path, "r") as f:
            raw_ym = f.read()
        parsed_ym = safe_parse_list_python(raw_ym)
        ym_val = parsed_ym[1:]

        # Controller computes u
        u_val = [-K * ym_val[0]]

        # Controller writes u
        u_wire = format_wire_python([simtime] + u_val)
        with open(u_path, "w") as f:
            f.write(u_wire)

        # Plant reads u
        with open(u_path, "r") as f:
            raw_u = f.read()
        parsed_u = safe_parse_list_python(raw_u)
        u_read = parsed_u[1:]

        # Plant computes next ym
        ym = [A * ym_val[0] + B * u_read[0]]
        simtime += 1.0

    shutil.rmtree(tmpdir, ignore_errors=True)
    return ym[0]


def run_loop_benchmarks():
    results = {}

    # Warmup
    simulate_control_loop(10)

    print(f"Control Loop Benchmarks ({N_LOOP_ITERS} iterations, {N_REPEATS} repeats)")
    print("=" * 70)

    r = bench(lambda: simulate_control_loop(N_LOOP_ITERS), N_REPEATS)
    results["loop_1000"] = r
    per_iter = r["median"] / N_LOOP_ITERS
    print(
        f"  1000-iter loop          : min={r['min'] * 1e3:.2f}ms  median={r['median'] * 1e3:.2f}ms"
    )
    print(f"  per iteration           : {per_iter * 1e6:.2f}μs")
    print(f"  loop rate               : {1.0 / per_iter:.0f} iters/sec")

    final_ym = simulate_control_loop(N_LOOP_ITERS)
    results["final_ym"] = final_ym
    print(f"  final ym (should -> 0)  : {final_ym:.6g}")

    print()
    return results


# ─── Latency distribution benchmarks ────────────────────────────────────────

LAT_N_SAMPLES = 50_000


def run_latency_benchmarks():
    results = {}

    print(f"Latency Distribution Benchmarks ({LAT_N_SAMPLES} samples each)")
    print("=" * 70)

    # Parse latencies
    d = latency_distribution(lambda: safe_parse_list_python(SMALL_INPUT), LAT_N_SAMPLES)
    results["parse_small"] = d
    print(
        f"  parse small  : p50={d['p50'] * 1e6:.2f}μs  p95={d['p95'] * 1e6:.2f}μs  "
        f"p99={d['p99'] * 1e6:.2f}μs  p99.9={d['p999'] * 1e6:.2f}μs"
    )

    d = latency_distribution(
        lambda: safe_parse_list_python(MEDIUM_INPUT), LAT_N_SAMPLES
    )
    results["parse_medium"] = d
    print(
        f"  parse medium : p50={d['p50'] * 1e6:.2f}μs  p95={d['p95'] * 1e6:.2f}μs  "
        f"p99={d['p99'] * 1e6:.2f}μs  p99.9={d['p999'] * 1e6:.2f}μs"
    )

    d = latency_distribution(lambda: format_wire_python(FORMAT_SMALL), LAT_N_SAMPLES)
    results["format"] = d
    print(
        f"  format small : p50={d['p50'] * 1e6:.2f}μs  p95={d['p95'] * 1e6:.2f}μs  "
        f"p99={d['p99'] * 1e6:.2f}μs  p99.9={d['p999'] * 1e6:.2f}μs"
    )

    # GC impact
    print()
    print("  GC Impact Analysis")
    print("  " + "-" * 50)

    gc_samples = 10_000
    times_no_gc = []
    times_with_gc = []

    gc.disable()
    for _ in range(gc_samples):
        t0 = time.perf_counter()
        safe_parse_list_python(MEDIUM_INPUT)
        times_no_gc.append(time.perf_counter() - t0)
    gc.enable()

    for i in range(gc_samples):
        if i % 100 == 0:
            gc.collect(0)  # generation 0 collection
        t0 = time.perf_counter()
        safe_parse_list_python(MEDIUM_INPUT)
        times_with_gc.append(time.perf_counter() - t0)

    times_no_gc.sort()
    times_with_gc.sort()

    p99_no_gc = times_no_gc[max(0, math.ceil(0.99 * gc_samples) - 1)]
    p999_no_gc = times_no_gc[max(0, math.ceil(0.999 * gc_samples) - 1)]
    p99_with_gc = times_with_gc[max(0, math.ceil(0.99 * gc_samples) - 1)]
    p999_with_gc = times_with_gc[max(0, math.ceil(0.999 * gc_samples) - 1)]

    results["gc_p99_no_gc"] = p99_no_gc
    results["gc_p999_no_gc"] = p999_no_gc
    results["gc_p99_with_gc"] = p99_with_gc
    results["gc_p999_with_gc"] = p999_with_gc

    print(
        f"    Parse (GC disabled) : p99={p99_no_gc * 1e6:.2f}μs  p99.9={p999_no_gc * 1e6:.2f}μs"
    )
    print(
        f"    Parse (GC enabled)  : p99={p99_with_gc * 1e6:.2f}μs  p99.9={p999_with_gc * 1e6:.2f}μs"
    )
    gc_impact = p999_with_gc / p999_no_gc if p999_no_gc > 0 else float("nan")
    results["gc_impact_ratio"] = gc_impact
    print(f"    GC impact (p99.9)   : {gc_impact:.2f}x")

    print()
    return results


# ─── Memory benchmarks ──────────────────────────────────────────────────────


def run_memory_benchmarks():
    results = {}

    print("Memory Usage Benchmarks")
    print("=" * 70)

    if not HAS_TRACEMALLOC:
        print("  tracemalloc not available -- skipping")
        results["available"] = "N/A"
        print()
        return results

    # Parse memory
    m = measure_peak_memory(lambda: safe_parse_list_python(SMALL_INPUT))
    results["parse_small_peak"] = m["peak_bytes"]
    results["parse_small_per_call"] = m["per_call_bytes"]
    print(
        f"  parse small  : peak={m['peak_bytes']} bytes  per_call={m['per_call_bytes']:.0f} bytes"
    )

    m = measure_peak_memory(lambda: safe_parse_list_python(MEDIUM_INPUT))
    results["parse_medium_peak"] = m["peak_bytes"]
    results["parse_medium_per_call"] = m["per_call_bytes"]
    print(
        f"  parse medium : peak={m['peak_bytes']} bytes  per_call={m['per_call_bytes']:.0f} bytes"
    )

    m = measure_peak_memory(lambda: safe_parse_list_python(LARGE_INPUT))
    results["parse_large_peak"] = m["peak_bytes"]
    results["parse_large_per_call"] = m["per_call_bytes"]
    print(
        f"  parse large  : peak={m['peak_bytes']} bytes  per_call={m['per_call_bytes']:.0f} bytes"
    )

    # Format memory
    m = measure_peak_memory(lambda: format_wire_python(FORMAT_SMALL))
    results["format_small_peak"] = m["peak_bytes"]
    print(f"  format small : peak={m['peak_bytes']} bytes")

    m = measure_peak_memory(lambda: format_wire_python(FORMAT_LARGE))
    results["format_large_peak"] = m["peak_bytes"]
    print(f"  format large : peak={m['peak_bytes']} bytes")

    # SHM note
    print()
    print("  Shared Memory: N/A")
    print("    Python has no built-in mmap + wire format IPC integration.")
    print(
        "    Julia's Mmap.jl provides zero-copy shared memory with minimal allocation."
    )
    results["shm"] = "N/A"

    print()
    return results


# ─── Output JSON for Julia runner ────────────────────────────────────────────


def main():
    print()
    print("=" * 70)
    print("  concore Python Benchmarks (Comprehensive)")
    print(f"  Python {sys.version.split()[0]} | {os.cpu_count()} CPUs")
    print("=" * 70)
    print()

    parser_results = run_parser_benchmarks()
    io_results = run_io_benchmarks()
    loop_results = run_loop_benchmarks()
    latency_results = run_latency_benchmarks()
    memory_results = run_memory_benchmarks()

    # Save machine-readable results for the Julia comparison runner
    all_results = {
        "parser": {k: v for k, v in parser_results.items()},
        "io": {k: v for k, v in io_results.items()},
        "loop": {k: v for k, v in loop_results.items()},
        "latency": {k: v for k, v in latency_results.items()},
        "memory": {k: v for k, v in memory_results.items()},
    }

    results_path = os.path.join(os.path.dirname(__file__), "python_results.json")
    with open(results_path, "w") as f:
        json.dump(all_results, f, indent=2, default=float)
    print(f"Results saved to {results_path}")


if __name__ == "__main__":
    main()
