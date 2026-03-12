# Concore.jl

[![CI](https://github.com/avinxshKD/concore.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/avinxshKD/concore.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/avinxshKD/concore.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/avinxshKD/concore.jl)
![Julia ≥ 1.10](https://img.shields.io/badge/julia-%E2%89%A5%201.10-blue)
[![License: LGPL v2.1](https://img.shields.io/badge/License-LGPL_v2.1-blue.svg)](https://www.gnu.org/licenses/lgpl-2.1)

A Julia implementation of the [concore](https://github.com/ControlCore-Project/concore) file-based IPC protocol for closed-loop peripheral neuromodulation control systems.

This is the **prototype / code challenge** for GSoC 2026 -- *"A Reference Implementation for concore Library in Julia"* under the [ControlCore-Project](https://github.com/ControlCore-Project) organization.

**Mentors:** Pradeeban Kathiravelu · Mayuresh Kothare · Rahul Jagwani

---

## What is concore?

[CONTROL-CORE](https://github.com/ControlCore-Project/concore) is a lightweight framework for closed-loop peripheral neuromodulation control systems. It lets separate OS processes -- controllers, plant models, observers -- talk to each other through small text files. The wire format is simple:

```
[simtime, value1, value2, ...]
```

There are existing implementations in Python (`concore.py`), C++ (`concore.hpp`), MATLAB (`import_concore.m`), and Verilog (`concore.v`). This project adds Julia to that list.

## Why Julia?

Julia sits at a nice intersection for this project -- it has Python-like readability but compiles to fast native code, which matters for real-time control loops. The standard library already ships `Mmap` for shared memory and there's good ZMQ support. Plus, Julia's type dispatch makes it straightforward to build a pluggable backend system without the boilerplate you'd need in Python.

## What this prototype covers

The goal was to prove feasibility: that a Julia node can participate in a mixed-language concore study alongside Python and C++ nodes, with full wire-format compatibility.

Here's what's implemented:

- **Core protocol** -- `concore_read`, `concore_write`, `initval`, `unchanged` (the full sync loop)
- **Port config & params** -- parsing `concore.iport`, `concore.oport`, `concore.params`
- **Safe parser** -- regex-based, no `eval()` or `Meta.parse()`. This matters because concore reads files written by other processes
- **4 transport backends** -- `FileBackend` (default), `DockerBackend` (absolute paths for containers), `SharedMemoryBackend` (Mmap.jl), `ZeroMQBackend` (ZMQ.jl)
- **Dual API** -- module-global API matching Python's `concore.simtime` pattern, plus a `ConCoreContext` API for explicit state management
- **Docker support** -- `detect_environment()`, `init_docker!()`, Dockerfile with Julia 1.10
- **PID controller** -- with anti-windup, separated into immutable params + mutable state
- **GraphML parsing** -- for extracting controller params from study graph files
- **Observability** -- `MetricsCollector` for latency/throughput tracking (zero-cost when disabled)
- **663+ test assertions** across 11 test suites
- **CI** -- GitHub Actions on Julia 1.8 / latest / nightly, Linux / macOS / Windows
- **Documenter.jl docs** -- API reference, getting started guide, backend docs

### What still needs work (proposed for GSoC)

The prototype is past feasibility. What remains is hardening, optimization, evidence packaging, and making the implementation easy for maintainers to evaluate and trust:

- **SHM performance regression** -- the shared memory backend currently re-mmaps on every read/write. The segment registry infrastructure is there; the fix is to keep the mmap buffer alive across operations
- **`concoredocker.jl` completion** -- the `DockerBackend` type and auto-detection work, but the full standalone `concoredocker.jl` needs to match `concoredocker.py`'s public interface exactly (same read/write/initval/unchanged surface with absolute paths)
- **Demo nodes for mixed studies** -- `demo/controller_jl.jl` and `demo/pm_jl.jl` running in a Docker-orchestrated study with Python nodes
- **Benchmark packaging** -- reproducible scripts with methodology docs, suitable for a research note
- **Landing the code upstream** -- PRs to the [main concore repo](https://github.com/ControlCore-Project/concore) dev branch

## Quick start

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

### Controller loop (module-global API)

This matches the Python concore pattern 1:1:

```julia
using Concore

Concore.delay = 0.01

u = initval("[0.0, 0.0]")

while Concore.simtime < Concore.maxtime
    while unchanged()
        ym = concore_read(1, "ym", "[0.0, 0.0]")
    end

    error_val = 100.0 - ym[1]
    u = [2.0 * error_val]

    concore_write(1, "u", u; delta=0)
end
```

### Context-based API (recommended for new Julia code)

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

> **Delta convention:** Controllers use `delta=0` (don't advance simtime). Plant models use `delta=1` (advance by 1 tick). Same as `demo/controller.py` and `demo/pm.py` upstream.

### Shared memory backend

```julia
ctx = ConCoreContext(backend=SharedMemoryBackend(8192), delay=0.001)
data = shm_read(ctx, 1, "ym", "[0.0, 0.0]")
shm_write(ctx, 1, "u", [42.0]; delta=0)
shm_cleanup()
```

### ZeroMQ backend

```julia
ctx = ConCoreContext(backend=ZeroMQBackend())
init_zmq_port("plant_out", :bind, "tcp://*:5555"; socket_type=:PUSH)
init_zmq_port("ctrl_in",  :connect, "tcp://localhost:5555"; socket_type=:PULL)
zmq_write("plant_out", "ym", [42.0, 3.14])
result = zmq_read("ctrl_in", "ym", "[0.0, 0.0]")
terminate_zmq()
```

## API mapping (Julia <-> Python <-> C++)

| Python (`concore.py`) | C++ (`concore.hpp`) | Julia (`Concore.jl`) |
|:---|:---|:---|
| `concore.read(port, name, initstr)` | `concore.read(port, name, initstr)` | `concore_read(port, name, initstr)` |
| `concore.write(port, name, val, delta)` | `concore.write(port, name, val, delta)` | `concore_write(port, name, val; delta)` |
| `concore.initval(str)` | `concore.initval(str)` | `initval(str)` |
| `concore.unchanged()` | `concore.unchanged()` | `unchanged()` |
| `concore.tryparam(name, default)` | -- | `tryparam(name, default)` |
| `concore.simtime` | `concore.simtime` | `Concore.simtime` |
| `concore.delay` | `concore.delay` | `Concore.delay` |
| -- | -- | `ConCoreContext(...)` *(Julia-only)* |
| -- | -- | `shm_read` / `shm_write` *(Julia-only)* |
| -- | -- | `zmq_read` / `zmq_write` *(Julia-only)* |

> `concore_read` / `concore_write` are prefixed to avoid shadowing Julia's `Base.read` / `Base.write`.

## Wire format compatibility

The parser handles everything the Python and C++ implementations produce, including numpy wrappers:

| Input | Parsed |
|:---|:---|
| `[1.0, 2.0, 3.0]` | `[1.0, 2.0, 3.0]` |
| `[np.float64(1.5), numpy.int32(2)]` | `[1.5, 2.0]` |
| `[np.array([1.0, 2.0])]` | `[1.0, 2.0]` |
| `[True, False, None]` | `[1.0, 0.0, 0.0]` |

Output uses `.0` suffix for integer-valued floats (`42.0` not `42`) to match Python's format byte-for-byte.

## Backend system

```
AbstractBackend
├── FileBackend           # relative paths ./in1/, ./out1/ (default)
├── DockerBackend         # absolute paths /in1/, /out1/ (containers)
├── SharedMemoryBackend   # memory-mapped files via Mmap.jl
└── ZeroMQBackend         # network sockets via ZMQ.jl
```

All backends share the same wire format, so you can mix them in a study -- e.g., a Julia node using `SharedMemoryBackend` can still talk to a Python node doing plain file I/O.

## Project structure

```
src/
├── Concore.jl          # module entry point, globals, exports
├── types.jl            # AbstractBackend hierarchy, ConCoreContext
├── parser.jl           # safe_parse_list (regex, no eval)
├── config.jl           # port/param/maxtime loading
├── protocol.jl         # concore_read, concore_write, unchanged, initval
├── docker.jl           # DockerBackend, detect_environment()
├── shm.jl              # SharedMemoryBackend via Mmap.jl
├── zmq.jl              # ZeroMQBackend via ZMQ.jl (optional dep)
├── observability.jl    # MetricsCollector for profiling
└── ConcoreUtils.jl     # PID controller, GraphML parsing

test/                   # 11 test suites, 663+ assertions
benchmark/              # 7 categories: parser, I/O, loop, SHM, memory, latency, multiprocess
demo/                   # standalone nodes, cross-language demo (Julia + Python)
docs/                   # Documenter.jl site
standalone/             # single-file distributions (concore.jl, concoredocker.jl)
```

## Dependencies

| Component | Deps |
|:---|:---|
| Core protocol | `Mmap` (stdlib) -- **zero external deps** |
| ZMQ backend | `ZMQ.jl` (optional, loaded on demand) |
| Utils (PID, GraphML) | `EzXML.jl` |

## Running tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Test breakdown:

| Suite | Assertions | What it covers |
|:---|---:|:---|
| `test_parser.jl` | 140 | wire format parsing, numpy, edge cases |
| `test_config.jl` | 79 | port files, param loading, maxtime |
| `test_protocol.jl` | 85 | read/write round-trips, formatting |
| `test_sync.jl` | 46 | unchanged() detection, initval |
| `test_interop.jl` | 88 | cross-language wire compat |
| `test_docker.jl` | 80 | Docker paths, detect_environment |
| `test_shm.jl` | 63 | shared memory read/write, cleanup |
| `test_zmq.jl` | 66 | ZeroMQ PUSH/PULL round-trip |
| `test_context.jl` | 155 | ConCoreContext API, state isolation |
| `test_utils.jl` | 165 | PID controller, anti-windup, GraphML |
| `test_observability.jl` | 136 | metrics, latency stats, export |

Integration tests in `test/integration/` cover end-to-end pipeline and wire format verification.

## Running benchmarks

```bash
julia benchmark/run_benchmarks.jl                # Julia only
julia benchmark/run_benchmarks.jl --with-python   # Julia vs Python comparison
```

Seven categories: parser throughput, file I/O latency, control loop timing, SHM vs file comparison, memory allocations, latency distributions (p50/p95/p99/p999), and multi-process IPC overhead. See [benchmark/README.md](benchmark/README.md) for methodology.

## Building docs

```bash
julia --project=docs/ -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs/ docs/make.jl
```

Opens at `docs/build/index.html`. Pages: getting started, API reference, backend details, cross-language interop, contributing.

## Design choices

- **No `eval` in the parser.** concore reads files written by other processes. Using `eval(Meta.parse(...))` on untrusted input is a security hole. The parser is pure regex + `tryparse(Float64, ...)`.
- **Module globals match Python exactly.** `Concore.simtime`, `Concore.delay`, `Concore.iport` -- makes it trivial to transliterate Python concore examples into Julia.
- **`ConCoreContext` exists alongside globals.** Globals are for compat; new Julia code should use the context API. Explicit, composable, no global mutation.
- **`Mmap.jl` for shared memory.** Julia stdlib, no POSIX `shm_open` bindings needed. Writes to the same paths as `FileBackend`, so other processes can still do plain file I/O.
- **ZMQ is optional.** Only loaded if you use `ZeroMQBackend`. Core protocol has zero external deps.
- **Sync string capped at 64 KB.** Without this, `s` grows forever in long simulations. The Python implementation has this bug -- fixed here.

## Benchmarks: Julia vs Python

Measured on AMD Ryzen 7 7435HS (16 threads), Julia 1.10.10, Linux x86_64. The Python comparison script (`bench_python_compare.py`, 559 lines) implements identical algorithms with identical inputs and iteration counts.

### Parse & format hot paths

| Benchmark | Julia | Python | Speedup |
|:---|:---|:---|:---|
| Parse small (2 elem) | 1.09 us | 4.05 us | **3.7x** |
| Parse medium (10 elem) | 2.51 us | 6.93 us | **2.8x** |
| Parse large (101 elem) | 18.0 us | 41.67 us | **2.3x** |
| Format small (2 elem) | 0.15 us | 0.60 us | **4.0x** |
| Format medium (10 elem) | 0.65 us | 1.99 us | **3.1x** |
| Format large (101 elem) | 7.0 us | 18.07 us | **2.6x** |

### End-to-end throughput

| Benchmark | Julia | Python | Speedup |
|:---|:---|:---|:---|
| Write throughput (ops/s) | 28,400 | 16,900 | **1.7x** |
| Read+parse throughput (ops/s) | 102,000 | 41,200 | **2.5x** |
| Control loop (1k iter) | 3,800 iter/s | 1,520 iter/s | **2.5x** |

Julia is 2-4x faster on every hot path. The parser gap narrows for larger inputs (regex overhead scales similarly), but the format path stays consistently faster because `IOBuffer` + direct float printing avoids Python's string concatenation overhead.

Full benchmark suite: `julia benchmark/run_benchmarks.jl --with-python`. Methodology in [benchmark/README.md](benchmark/README.md).

## What's next

This prototype proves Julia can participate in concore studies with full wire-format compatibility. The remaining work for GSoC -- hardening the SHM backend, completing `concoredocker.jl`, landing demo nodes in a mixed Docker study, and packaging the benchmarks into a research note -- is scoped in the proposal.

## References

- [concore repository](https://github.com/ControlCore-Project/concore) -- Python, C++, Verilog, MATLAB implementations (PRs go to [dev branch](https://github.com/ControlCore-Project/concore/tree/dev))
- [concore paper](https://doi.org/10.1109/ACCESS.2022.3161471) -- S. Kathiravelu et al., "CONTROL-CORE: A Framework for Simulation and Design of Closed-Loop Peripheral Neuromodulation Control Systems," IEEE Access, 2022
- [concore documentation](https://control-core.readthedocs.io/en/latest/index.html) -- ReadTheDocs
- [GSoC 2026 project page](https://summerofcode.withgoogle.com/) -- Google Summer of Code

## License

LGPL-2.1 -- following the [concore project licensing](https://github.com/ControlCore-Project/concore/blob/main/LICENSE).
