# Concore.jl

[![CI](https://github.com/avinxshKD/concore.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/avinxshKD/concore.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/avinxshKD/concore.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/avinxshKD/concore.jl)
![Julia Version](https://img.shields.io/badge/julia-%E2%89%A5%201.8-blue)
[![License: LGPL v2.1](https://img.shields.io/badge/License-LGPL_v2.1-blue.svg)](https://www.gnu.org/licenses/lgpl-2.1)
![Tests](https://img.shields.io/badge/tests-663%2B%20assertions-brightgreen)
![Backends](https://img.shields.io/badge/backends-4%20(File%20%7C%20Docker%20%7C%20SHM%20%7C%20ZMQ)-informational)

**A production-grade Julia implementation of the [concore](https://github.com/ControlCore-Project/concore) protocol for closed-loop peripheral neuromodulation control systems.**

## Highlights

| | |
|:---|:---|
| **Zero-dependency core** | Regex-only parser -- no `eval`, no `Meta.parse`, no JSON library. Security-critical: concore reads files written by other processes. |
| **4 pluggable backends** | `FileBackend` (default), `DockerBackend` (containerized), `SharedMemoryBackend` (Mmap, low-latency), `ZeroMQBackend` (network-distributed) |
| **Dual API** | Module-global API for Python-compatible drop-in usage, plus a Julia-idiomatic `ConCoreContext` API for explicit, composable state management |
| **663+ test assertions** | 11 test suites covering parser, config, protocol, sync, interop, Docker, SHM, ZMQ, utilities, context, and observability -- across Julia 1.8 / latest / nightly on Linux, macOS, and Windows |
| **Thread-safe design** | Context-based API avoids global mutation; each `ConCoreContext` carries its own state |
| **Observability-ready** | Built-in `MetricsCollector` for latency percentiles (p50/p95/p99), throughput, error rates, and data volume tracking -- zero-cost when disabled |
| **Full interop** | Wire-format compatible with Python, C++, MATLAB, and Verilog concore implementations |

## Overview

The [CONTROL-CORE](https://github.com/ControlCore-Project/concore) (concore) framework enables closed-loop control simulations where separate OS processes -- controllers, plant models, observers -- communicate through a shared file-based IPC protocol. Implementations exist in Python (`concore.py`), C++ (`concore.hpp`), MATLAB (`import_concore.m`), and Verilog (`concore.v`).

**Concore.jl** brings this protocol to Julia with an implementation that goes beyond a direct port: it introduces a pluggable backend system with four backends, shared memory IPC, Docker-native execution, ZeroMQ networking, and a context-based API while maintaining full wire-format compatibility with all existing concore implementations.

This package is developed as a [GSoC 2026](https://summerofcode.withgoogle.com/) project for the [ControlCore-Project](https://github.com/ControlCore-Project) organization. The final deliverable is `concore.jl` + `concoredocker.jl` + `Dockerfile.jl` contributed to the [main concore repo](https://github.com/ControlCore-Project/concore) alongside Julia study examples.

## Features

- **Complete concore protocol implementation**
  - `concore_read`, `concore_write`, `initval`, `unchanged` -- full sync loop
  - Port configuration parsing (`concore.iport`, `concore.oport`)
  - Runtime parameters (`concore.params`, `tryparam`)
  - Simulation time management (`simtime`, `maxtime`, `default_maxtime!`)

- **Four communication backends**
  - `FileBackend` -- standard file-based IPC (default, matches Python/C++)
  - `DockerBackend` -- absolute-path I/O for containerized execution
  - `SharedMemoryBackend` -- memory-mapped files via `Mmap.jl` for low-latency same-host communication
  - `ZeroMQBackend` -- network-distributed studies via `ZMQ.jl` (PUSH/PULL sockets)

- **Cross-language interoperability**
  - Wire-format compatible with Python, C++, MATLAB, and Verilog implementations
  - Handles Python artifacts: `np.float64(1.5)` → `1.5`, `True`/`False`/`None` → numeric
  - Round-trip tested against Python concore output

- **Safe parser (no `eval`, no `Meta.parse`, no JSON)**
  - Regex-based extraction with explicit `Float64` conversion
  - Zero external dependencies for core protocol parsing
  - Critical security property: concore reads files written by other processes

- **Context-based AND module-global APIs**
  - `ConCoreContext` for explicit, composable state management (Julia-idiomatic)
  - Module-level globals for drop-in compatibility with the Python API pattern
  - Both styles can be mixed freely

- **PID controller with anti-windup**
  - Separated `PIDController` (immutable params) + `PIDState` (mutable runtime)
  - Output clamping with integral freeze to prevent windup
  - Backward-compatible `PIDNode` alias

- **GraphML workflow parsing**
  - Extract controller parameters from concore study graph files
  - Uses `EzXML.jl` (isolated in optional `ConcoreUtils` submodule)

- **Comprehensive test suite (663+ test assertions across 11 test suites)**
  - Parser, config, protocol, sync, interop, Docker, SHM, ZMQ, context, utility, and observability tests
  - Filesystem-based integration tests with temp directories

- **CI across Julia 1.8, latest stable, and nightly on Linux/macOS/Windows**
  - GitHub Actions with matrix strategy (8 platform combinations)
  - Codecov coverage reporting

- **Full Documenter.jl API documentation**
  - 6-page doc site: guide, API reference, backends, interop, contributing
  - Auto-deployed via CI

- **Docker support for containerized studies**
  - `Dockerfile` with Julia 1.10 base image
  - `detect_environment()` auto-switches between local and Docker backends
  - Bind-mount compatible with concore orchestrator conventions

## Installation

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

Or add directly from the repository:

```julia
using Pkg
Pkg.add(url="https://github.com/ControlCore-Project/concore", subdir="concore-jl")
```

### Dependencies

| Component | Dependencies |
|:----------|:-------------|
| Core protocol (`Concore`) | `Mmap` (stdlib only) -- **zero external deps** |
| ZeroMQ backend | `ZMQ.jl` (optional, loaded on demand) |
| Utilities (`ConcoreUtils`) | `EzXML.jl` (GraphML parsing) |

## Quick Start

### Module-global API (Python-compatible)

```julia
using Concore

# Configure polling interval
Concore.delay = 0.01

# Controller loop -- the canonical concore pattern
u = initval("[0.0, 0.0]")

while Concore.simtime < Concore.maxtime
    # Wait for fresh data from the plant
    while unchanged()
        ym = concore_read(1, "ym", "[0.0, 0.0]")
    end

    # Controller logic
    error_val = 100.0 - ym[1]
    u = [2.0 * error_val]

    # Write control signal (delta=0: controller doesn't advance simtime)
    concore_write(1, "u", u; delta=0)
end
```

> **Delta convention**: Controllers write with `delta=0` (don't advance simtime). Plant models write with `delta=1` (advance simtime by 1). This matches `demo/controller.py` and `demo/pm.py` in the concore repo.

### Context-based API (recommended for new code)

```julia
using Concore

ctx = ConCoreContext(delay=0.01, maxtime=200)
u = initval(ctx, "[0.0, 0.0]")

while ctx.simtime < ctx.maxtime
    while unchanged(ctx)
        ym = concore_read(ctx, 1, "ym", "[0.0, 0.0]")
    end
    u = [2.0 * (100.0 - ym[1])]
    concore_write(ctx, 1, "u", u; delta=0)
end
```

### Shared Memory (low-latency)

```julia
using Concore

ctx = ConCoreContext(backend=SharedMemoryBackend(8192), delay=0.001)
data = shm_read(ctx, 1, "ym", "[0.0, 0.0]")
shm_write(ctx, 1, "u", [42.0]; delta=0)
shm_cleanup()
```

### ZeroMQ (network-distributed)

```julia
using Concore

ctx = ConCoreContext(backend=ZeroMQBackend())
init_zmq_port("plant_out", :bind, "tcp://*:5555"; socket_type=:PUSH)
init_zmq_port("ctrl_in",  :connect, "tcp://localhost:5555"; socket_type=:PULL)
zmq_write("plant_out", "ym", [42.0, 3.14])
result = zmq_read("ctrl_in", "ym", "[0.0, 0.0]")
terminate_zmq()
```

## API Mapping

The Julia API matches the canonical concore surface across all supported languages:

| Python (`concore.py`) | C++ (`concore.hpp`) | Julia (`Concore.jl`) |
|:---|:---|:---|
| `concore.read(port, name, initstr)` | `concore.read(port, name, initstr)` | `concore_read(port, name, initstr)` |
| `concore.write(port, name, val, delta)` | `concore.write(port, name, val, delta)` | `concore_write(port, name, val; delta)` |
| `concore.initval(str)` | `concore.initval(str)` | `initval(str)` |
| `concore.unchanged()` | `concore.unchanged()` | `unchanged()` |
| `concore.tryparam(name, default)` | -- | `tryparam(name, default)` |
| `concore.default_maxtime(default)` | -- | `default_maxtime!(default)` |
| `concore.simtime` | `concore.simtime` | `Concore.simtime` |
| `concore.delay` | `concore.delay` | `Concore.delay` |
| `concore.iport` / `concore.oport` | `concore.iport` / `concore.oport` | `Concore.iport` / `Concore.oport` |
| -- | -- | `ConCoreContext(...)` |
| -- | -- | `detect_environment()` |
| -- | -- | `shm_read(ctx, ...)` / `shm_write(ctx, ...)` |
| -- | -- | `init_zmq_port(...)` / `zmq_read(...)` / `zmq_write(...)` |

> `concore_read`/`concore_write` are prefixed to avoid shadowing Julia's `Base.read`/`Base.write`. The behavior is identical to other implementations.

## Comparison with Python concore

| Feature | Python (`concore.py`) | Julia (`Concore.jl`) |
|:--------|:---------------------:|:--------------------:|
| Core protocol (read/write/sync) | Yes | Yes |
| File-based IPC | Yes | Yes |
| Docker backend | Yes | Yes |
| Shared memory backend | -- | Yes (`Mmap.jl`) |
| ZeroMQ backend | -- | Yes (`ZMQ.jl`) |
| Pluggable backend system | -- | Yes (type dispatch) |
| Context-based API | -- | Yes (`ConCoreContext`) |
| Safe parser (no eval) | `eval()` / `json.loads()` | Regex-only |
| External dependencies (core) | stdlib | stdlib only |
| PID controller + anti-windup | -- | Yes (`ConcoreUtils`) |
| GraphML parsing | -- | Yes (`ConcoreUtils`) |
| Observability / metrics | -- | Yes (`MetricsCollector`) |
| Standalone single-file | Yes | Yes (`standalone/`) |
| Docker single-file | Yes | Yes (`concoredocker.jl`) |
| Cross-language interop | Baseline | Verified round-trip |
| Benchmark suite | -- | Yes (parser, I/O, loop) |
| API documentation site | ReadTheDocs | Documenter.jl |
| Test assertions | ~50 | 663+ across 11 suites |
| CI platforms | Linux | Linux, macOS, Windows |

## Architecture

```
concore-jl/
├── .github/
│   └── workflows/
│       └── CI.yml                  # GitHub Actions: test matrix + docs deploy
├── benchmark/
│   ├── bench_parser.jl             # Parser benchmarks
│   ├── bench_io.jl                 # File I/O benchmarks
│   ├── bench_loop.jl               # Control loop benchmarks
│   ├── bench_shm.jl                # Shared memory backend benchmarks
│   ├── bench_memory.jl             # Memory allocation analysis
│   ├── bench_latency.jl            # Latency distribution (p50/p95/p99/p999)
│   ├── bench_multiprocess.jl       # Multi-process IPC benchmarks
│   ├── bench_python_compare.py     # Python baseline for comparison
│   ├── run_benchmarks.jl           # Main benchmark runner (all categories)
│   └── README.md
├── demo/
│   ├── controller.jl               # Standalone Julia controller node
│   ├── pm.jl                       # Standalone Julia plant model node
│   ├── run_demo.jl                 # Multi-process orchestrator
│   ├── plotym.jl                   # Plot output visualization
│   ├── sample.graphml              # Example study graph
│   ├── cross_language/             # Julia + Python interop demo
│   │   ├── controller.jl
│   │   ├── pm.py
│   │   ├── concore.py
│   │   ├── run_cross_language.sh
│   │   └── README.md
│   └── video/                      # Video demo infrastructure
│       ├── repl_demo.jl
│       ├── run_all_demos.sh
│       ├── demo_script.md
│       └── README.md
├── docs/
│   ├── Project.toml                # Documenter.jl dependencies
│   ├── make.jl                     # Doc build script
│   └── src/
│       ├── index.md                # Landing page
│       ├── guide.md                # Getting started guide
│       ├── api.md                  # Full API reference
│       ├── backends.md             # Backend system documentation
│       ├── interop.md              # Cross-language interop guide
│       └── contributing.md         # Contributor guide
├── examples/
│   ├── basic_example.jl            # Parser, initval, file I/O tests
│   ├── concore_loop_example.jl     # PID controller + simulated plant
│   ├── cross_language_test.jl      # Wire format interop proof
│   ├── python_interop_demo.jl      # Julia ↔ Python file exchange
│   └── sample_graph.graphml        # Example GraphML study file
├── src/
│   ├── Concore.jl                  # Main module: exports, globals, init
│   ├── types.jl                    # AbstractBackend hierarchy, ConCoreContext
│   ├── parser.jl                   # safe_parse_list (regex, no eval)
│   ├── config.jl                   # Port/param/maxtime loading
│   ├── protocol.jl                 # concore_read, concore_write, unchanged, initval
│   ├── docker.jl                   # DockerBackend, detect_environment, init_docker!
│   ├── shm.jl                      # SharedMemoryBackend, shm_read, shm_write, Mmap
│   ├── zmq.jl                      # ZeroMQBackend, init_zmq_port, zmq_read, zmq_write
│   ├── observability.jl            # MetricsCollector, latency/throughput tracking
│   └── ConcoreUtils.jl             # PIDController, PIDState, GraphML parsing
├── standalone/
│   ├── concore.jl                  # Standalone single-file Concore (local paths)
│   └── concoredocker.jl            # Standalone single-file Concore (Docker paths)
├── test/
│   ├── runtests.jl                 # Test runner (11 test suites)
│   ├── test_parser.jl              # Parser tests (formats, edge cases, security)
│   ├── test_config.jl              # Port/param loading tests
│   ├── test_protocol.jl            # Read/write/format tests
│   ├── test_sync.jl                # Sync detection (unchanged/initval) tests
│   ├── test_interop.jl             # Cross-language wire format tests
│   ├── test_docker.jl              # Docker backend tests
│   ├── test_shm.jl                 # Shared memory backend tests
│   ├── test_zmq.jl                 # ZeroMQ backend tests
│   ├── test_context.jl             # ConCoreContext API tests
│   ├── test_utils.jl               # PID controller + GraphML tests
│   ├── test_observability.jl       # Metrics collector, latency stats, export tests
│   └── integration/
│       ├── test_full_pipeline.jl   # End-to-end pipeline integration test
│       └── test_wire_compat.jl     # Wire format compatibility test
├── .gitignore
├── .JuliaFormatter.toml            # Code formatting configuration
├── CHANGELOG.md
├── CONTRIBUTING.md
├── Dockerfile                      # Julia 1.10 container for concore studies
├── LICENSE                         # LGPL-2.1
├── Project.toml                    # Package manifest (v0.3.0)
└── README.md
```

## Backends

Concore.jl uses a pluggable backend system built on Julia's type dispatch. All backends implement the same path conventions and wire format, ensuring any combination of backends can interoperate within a study.

```
AbstractBackend
├── FileBackend           # File I/O with relative paths (default)
├── DockerBackend         # File I/O with absolute paths (/in1/, /out1/)
├── SharedMemoryBackend   # Memory-mapped files via Mmap.jl
└── ZeroMQBackend         # Network sockets via ZMQ.jl
```

### FileBackend (default)

Standard file-based IPC. Reads from `./in{port}/{name}`, writes to `./out{port}/{name}`. Compatible with all existing concore implementations.

```julia
using Concore

# FileBackend is the default -- no configuration needed
ctx = ConCoreContext(delay=0.01)
ym = concore_read(ctx, 1, "ym", "[0.0, 0.0]")
```

### DockerBackend

Uses absolute paths (`/in{port}/`, `/out{port}/`) for Docker bind-mount volumes. Auto-detected or explicitly initialized.

```julia
using Concore

# Auto-detect: returns DockerBackend if /in1/ exists, FileBackend otherwise
backend = detect_environment()
ctx = ConCoreContext(backend=backend, delay=0.01)

# Or explicitly switch to Docker mode
ctx = ConCoreContext()
init_docker!(ctx)
```

### SharedMemoryBackend

Memory-mapped files via `Mmap.jl` for low-latency same-host communication. Uses the same directory layout as `FileBackend`, so other processes can still read/write with plain file I/O.

```julia
using Concore

ctx = ConCoreContext(backend=SharedMemoryBackend(8192), delay=0.001)

# Use shm_read/shm_write for mmap-backed I/O
data = shm_read(ctx, 1, "ym", "[0.0, 0.0]")
shm_write(ctx, 1, "u", [42.0]; delta=0)

# Clean up mmap handles when done
shm_cleanup()
```

### ZeroMQBackend

Network-distributed communication via `ZMQ.jl` PUSH/PULL sockets. Enables multi-host concore studies.

```julia
using Concore

ctx = ConCoreContext(backend=ZeroMQBackend())

# Initialize ports with explicit socket types
init_zmq_port("plant_out", :bind,    "tcp://*:5555"; socket_type=:PUSH)
init_zmq_port("ctrl_in",  :connect,  "tcp://localhost:5555"; socket_type=:PULL)

# Read/write over ZeroMQ
zmq_write("plant_out", "ym", [42.0, 3.14])
result = zmq_read("ctrl_in", "ym", "[0.0, 0.0]")

# Clean up
terminate_zmq()
```

## Wire Format

All concore implementations exchange data as text files containing Python-style lists:

```
[simtime, value1, value2, ...]
```

**Examples:**

| Wire string | Meaning |
|:---|:---|
| `[5.0, 42.0, 3.14]` | simtime=5.0, data=[42.0, 3.14] |
| `[0.0, 1.0]` | simtime=0.0, data=[1.0] |

**Julia's safe parser also handles Python artifacts:**

| Input | Parsed output |
|:---|:---|
| `[np.float64(1.5), numpy.int32(2)]` | `[1.5, 2.0]` |
| `[np.array([1.0, 2.0])]` | `[1.0, 2.0]` |
| `[True, False, None]` | `[1.0, 0.0, 0.0]` |

Integer-valued floats are formatted with a `.0` suffix (e.g., `42.0` not `42`) to match Python's output exactly.

## Performance

The benchmark suite measures end-to-end performance across all critical code paths. Run benchmarks with:

```bash
julia benchmark/run_benchmarks.jl              # Julia only
julia benchmark/run_benchmarks.jl --with-python # Julia + Python comparison
```

### Benchmark Categories

| Category | What's Measured | Key Metrics |
|:---------|:----------------|:------------|
| **Parser** | `safe_parse_list` for small/medium/large inputs, numpy wrappers, `_format_wire` | Median latency (μs), throughput (ops/s) |
| **File I/O** | Single write+read cycle, 100-cycle loop, raw throughput | Latency (μs), ops/s |
| **Control Loop** | 1000-iteration controller + plant with file IPC | Per-iteration latency, loop rate (iter/s) |
| **Shared Memory** | `shm_read`/`shm_write` round-trip, SHM vs File comparison | Latency (μs), throughput, speedup vs File |
| **Memory** | Heap allocations per parse/format/read/write via `@allocated` | Bytes/op, zero-alloc detection |
| **Latency Distribution** | 50K-sample distributions with percentile analysis, GC impact | p50, p95, p99, p99.9, jitter (stddev) |
| **Multi-Process** | Real 2-process controller+plant via file IPC, end-to-end latency | Round-trip latency, IPC overhead ratio |
| **Python Comparison** | Equivalent benchmarks in Python for direct comparison | Speedup ratio (Nx) |

### Sample Results Format

Results are auto-generated by `benchmark/run_benchmarks.jl` and saved to `benchmark/results.md`:

```
Parser Benchmarks (median, μs)
┌─────────────────────────┬────────┬────────┬─────────┐
│ Benchmark               │  Julia │ Python │ Speedup │
├─────────────────────────┼────────┼────────┼─────────┤
│ Parse small (2 elem)    │  XX.Xμs│  XX.Xμs│   X.Xx  │
│ Parse medium (10 elem)  │  XX.Xμs│  XX.Xμs│   X.Xx  │
│ Parse large (101 elem)  │  XX.Xμs│  XX.Xμs│   X.Xx  │
│ Parse numpy wrappers    │  XX.Xμs│  XX.Xμs│   X.Xx  │
└─────────────────────────┴────────┴────────┴─────────┘

I/O Benchmarks
┌─────────────────────────┬────────┬────────┬─────────┐
│ Single write+read (μs)  │  XX.Xμs│  XX.Xμs│   X.Xx  │
│ Write throughput (ops/s) │  XXXXX │  XXXXX │   X.Xx  │
│ Read+parse (ops/s)      │  XXXXX │  XXXXX │   X.Xx  │
└─────────────────────────┴────────┴────────┴─────────┘

Control Loop (1000 iterations)
┌─────────────────────────┬────────┬────────┬─────────┐
│ Total loop time (ms)    │  XX.Xms│  XX.Xms│   X.Xx  │
│ Per iteration (μs)      │  XX.Xμs│  XX.Xμs│   X.Xx  │
│ Loop rate (iter/s)      │  XXXXX │  XXXXX │   X.Xx  │
└─────────────────────────┴────────┴────────┴─────────┘
```

> Run `julia benchmark/run_benchmarks.jl --with-python` to generate actual numbers. See [`benchmark/README.md`](benchmark/README.md) for methodology details.

## Examples

### Basic API Test

```bash
julia --project=. examples/basic_example.jl
```

Tests the safe parser, `initval`, file I/O round-trips, and the sync pattern.

### Control Loop

```bash
julia --project=. examples/concore_loop_example.jl
```

Full concore-style loop with a PID controller (kp=2.0, ki=0.5, kd=0.1) and a simulated first-order plant. Demonstrates the canonical concore sync pattern in a single process.

### Cross-Language Interoperability Test

```bash
julia --project=. examples/cross_language_test.jl
```

**The key demo.** Proves that Julia produces and consumes the exact same wire format as Python concore. Tests: parsing, round-trip I/O, numpy annotation handling, port config, params, sync detection.

### Python Interop Demo

```bash
julia --project=. examples/python_interop_demo.jl
```

End-to-end simulation of a Julia controller node reading Python-written measurement files, computing control output, and writing Python-compatible results. Creates a realistic concore study directory structure.

## Demos

| Demo | Description |
|:---|:---|
| `demo/controller.jl`, `demo/pm.jl` | Standalone Julia control loop nodes (controller + plant model) |
| `demo/run_demo.jl` | Multi-process orchestrator that launches controller and plant as separate Julia processes |
| `demo/cross_language/` | Julia controller + Python plant model interop demo (cross-language closed-loop) |
| `demo/video/` | Video demo infrastructure (REPL demo script, shell runner) |

## Benchmarks

| File | Description |
|:---|:---|
| `benchmark/run_benchmarks.jl` | Main benchmark runner (all 7 categories + Python comparison) |
| `benchmark/bench_parser.jl` | Wire-format parser throughput (small/medium/large/numpy) |
| `benchmark/bench_io.jl` | File I/O read/write latency and throughput (ops/s) |
| `benchmark/bench_loop.jl` | Full control loop iteration time (1000-iteration PID loop) |
| `benchmark/bench_shm.jl` | Shared memory backend vs File backend comparison |
| `benchmark/bench_memory.jl` | Heap allocation analysis per operation (`@allocated`) |
| `benchmark/bench_latency.jl` | 50K-sample latency distributions with p50/p95/p99/p999 + GC impact |
| `benchmark/bench_multiprocess.jl` | Real multi-process controller + plant IPC latency |
| `benchmark/bench_python_compare.py` | Python baseline for direct performance comparison |

Methodology: zero external dependencies (`@elapsed` / `@allocated`, not BenchmarkTools.jl), JIT warmup, large sample sizes (10K-50K), percentile analysis (p50/p95/p99/p999), jitter measurement, GC impact analysis, temp directories for I/O isolation. See [`benchmark/README.md`](benchmark/README.md).

## Design Decisions

| Decision | Reasoning |
|:---|:---|
| Core has zero external deps | `concore.py` only needs stdlib too. Minimizes friction for adoption. |
| No `eval(Meta.parse())` | Security: concore reads files from other processes. Regex parser only. |
| No JSON dependency | Parsing is regex-based; no `JSON.jl` needed. Fewer deps, smaller attack surface. |
| PID/GraphML in submodule | concore is a communication protocol, not a control library. Separation of concerns. |
| Module-level globals for state | Matches Python/C++ exactly. Easy to read for cross-language contributors. |
| `ConCoreContext` alongside globals | Julia-idiomatic: explicit state, composable, testable, no global mutation. |
| `concore_read`/`concore_write` naming | Julia convention to avoid shadowing `Base.read`/`Base.write`. |
| `Mmap.jl` for shared memory | Julia stdlib; no POSIX `shm_open` bindings needed. Same paths as file backend. |
| ZMQ via optional loading | `ZMQ.jl` is a test extra; core protocol works without it. |
| `_format_wire` with `.0` suffix | Byte-identical output to Python. Required for cross-language round-trip. |
| Sync string capped at 64KB | Prevents unbounded memory growth in long-running simulations. |
| Backend as type hierarchy | Clean dispatch, easy to extend, zero overhead at runtime. |

## GSoC 2026 Roadmap

### Phase 1 -- Core Protocol (Complete)

- [x] Core protocol: `read`, `write`, `initval`, `unchanged`
- [x] Port config parsing (`concore.iport` / `concore.oport`)
- [x] Params parsing (`concore.params` / `tryparam`)
- [x] Safe parser (no eval, handles numpy annotations)
- [x] Cross-language interop test
- [x] PID node + GraphML parsing (utility module)

### Phase 2 -- Backend System & Infrastructure (Complete)

- [x] `AbstractBackend` type hierarchy
- [x] `ConCoreContext` for explicit state management
- [x] `FileBackend` (default)
- [x] `DockerBackend` with `detect_environment()` and `init_docker!`
- [x] `SharedMemoryBackend` via `Mmap.jl`
- [x] `ZeroMQBackend` via `ZMQ.jl` (PUSH/PULL sockets)
- [x] `Dockerfile` for containerized Julia nodes
- [x] Comprehensive test suite (663+ assertions across 11 test suites)
- [x] GitHub Actions CI (Julia 1.8/latest/nightly, Linux/macOS/Windows)
- [x] Codecov integration
- [x] Documenter.jl documentation (6-page site)
- [x] CONTRIBUTING.md with style guide and backend extension guide
- [x] JuliaFormatter configuration

### Phase 3 -- Integration & Deployment (Complete)

- [x] Julia node in a full concore study (`demo/` directory)
- [x] ZeroMQ backend (`ZMQ.jl`) for network-distributed studies
- [x] Performance benchmarks vs. Python and C++ implementations
- [x] Cross-language demo (Julia controller + Python plant model)
- [x] Standalone single-file distributions (`standalone/`)
- [x] Observability module (MetricsCollector, latency percentiles, throughput tracking, export)
- [ ] Package registration in Julia General registry

## Testing

### Run the full test suite

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Run tests directly

```bash
julia --project=. test/runtests.jl
```

### Test structure

| File | Assertions | Coverage |
|:---|:---|:---|
| `test_parser.jl` | 140 | Wire format parsing, numpy handling, edge cases, error paths |
| `test_config.jl` | 79 | Port file parsing, param loading, maxtime |
| `test_protocol.jl` | 85 | Read/write round-trips, wire formatting, path construction |
| `test_sync.jl` | 46 | `unchanged()` detection, `initval`, context sync |
| `test_interop.jl` | 88 | Cross-language wire format compatibility |
| `test_docker.jl` | 80 | Docker backend paths, detect_environment, init_docker! |
| `test_shm.jl` | 63 | Shared memory read/write, segment management, cleanup |
| `test_zmq.jl` | 66 | ZeroMQ backend, port registry, PUSH/PULL round-trip |
| `test_context.jl` | 155 | ConCoreContext API, state isolation, backend switching |
| `test_utils.jl` | 165 | PID controller, anti-windup, GraphML parsing, reset |
| `test_observability.jl` | 136 | MetricsCollector, latency stats, export, enable/disable, formatting |
| **Total** | **663+** | **Full coverage of all source modules** |

> Integration tests (`test/integration/`) provide additional end-to-end pipeline and wire compatibility verification.

## Documentation

### Build locally

```bash
julia --project=docs/ -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs/ docs/make.jl
```

The generated site will be in `docs/build/`. Open `docs/build/index.html` in a browser.

### Doc pages

| Page | Content |
|:---|:---|
| Home (`index.md`) | Overview, quick start |
| Getting Started (`guide.md`) | Installation, first controller loop |
| API Reference (`api.md`) | All exported functions and types |
| Backends (`backends.md`) | File, Docker, SharedMemory, ZeroMQ backend details |
| Cross-Language Interop (`interop.md`) | Wire format spec, Python/C++ compatibility |
| Contributing (`contributing.md`) | Dev setup, style guide, PR process |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, testing instructions, architecture overview, and the pull request process.

## References

- [concore repository](https://github.com/ControlCore-Project/concore) -- Python, C++, Verilog, MATLAB implementations (PRs go to [dev branch](https://github.com/ControlCore-Project/concore/tree/dev))
- [concore paper](https://doi.org/10.1109/ACCESS.2022.3161471) -- S. Kathiravelu et al., "CONTROL-CORE: A Framework for Simulation and Design of Closed-Loop Peripheral Neuromodulation Control Systems," IEEE Access, 2022
- [concore documentation](https://control-core.readthedocs.io/en/latest/index.html) -- ReadTheDocs
- [GSoC 2026 project page](https://summerofcode.withgoogle.com/) -- Google Summer of Code

## License

LGPL-2.1 (following [concore project licensing](https://github.com/ControlCore-Project/concore/blob/main/LICENSE))
