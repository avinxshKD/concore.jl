# Concore.jl

[![CI](https://github.com/avinxshKD/concore.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/avinxshKD/concore.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/avinxshKD/concore.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/avinxshKD/concore.jl)
![Julia ≥ 1.10](https://img.shields.io/badge/julia-%E2%89%A5%201.10-blue)
[![License: LGPL v2.1](https://img.shields.io/badge/License-LGPL_v2.1-blue.svg)](https://www.gnu.org/licenses/lgpl-2.1)

A Julia implementation of the [concore](https://github.com/ControlCore-Project/concore) file-based IPC protocol for closed-loop peripheral neuromodulation control systems.

This repository is the GSoC 2026 prototype for **“A Reference Implementation for concore Library in Julia”** under [ControlCore-Project](https://github.com/ControlCore-Project).

**Mentors:** Pradeeban Kathiravelu · Mayuresh Kothare · Rahul Jagwani

---

## TL;DR

- Wire-compatible Julia implementation of concore protocol semantics
- Safe parser for cross-process input (`eval`-free)
- Multiple backends: file, docker-path, shared memory, ZeroMQ
- Compatibility API + explicit `ConCoreContext` API
- Tests, CI, benchmarks, and docs are in this repo

## Why this exists

[CONTROL-CORE](https://github.com/ControlCore-Project/concore) coordinates controller/plant/observer processes through a minimal wire format:

```
[simtime, value1, value2, ...]
```

Python, C++, MATLAB, and Verilog implementations already exist. This project adds a Julia implementation for mixed-language studies.

## Status

| Feature | Status | Evidence |
|:---|:---|:---|
| Wire compatibility | Implemented, tested | [test/test_interop.jl](test/test_interop.jl), [test/integration/test_wire_compat.jl](test/integration/test_wire_compat.jl) |
| Core protocol (`concore_read`, `concore_write`, `initval`, `unchanged`) | Implemented, tested | [test/test_protocol.jl](test/test_protocol.jl), [test/test_sync.jl](test/test_sync.jl) |
| Config/params loading | Implemented, tested | [test/test_config.jl](test/test_config.jl) |
| Shared memory backend | Implemented, tested | [src/shm.jl](src/shm.jl), [test/test_shm.jl](test/test_shm.jl) |
| ZeroMQ backend | Implemented, tested | [src/zmq.jl](src/zmq.jl), [test/test_zmq.jl](test/test_zmq.jl) |
| Context API | Implemented, tested | [src/types.jl](src/types.jl), [test/test_context.jl](test/test_context.jl) |
| Benchmark harness | Implemented | [benchmark/run_benchmarks.jl](benchmark/run_benchmarks.jl), [benchmark/bench_python_compare.py](benchmark/bench_python_compare.py) |
| Standalone `concoredocker.jl` parity | In progress | [standalone/concoredocker.jl](standalone/concoredocker.jl) |

## What is implemented

- Core protocol: `concore_read`, `concore_write`, `initval`, `unchanged`
- Config loading from `concore.iport`, `concore.oport`, `concore.params`
- Safe numeric parser with numpy-wrapper handling
- Backends:
    - `FileBackend` (default)
    - `DockerBackend` (absolute container paths)
    - `SharedMemoryBackend` (Mmap)
    - `ZeroMQBackend` (optional)
- APIs:
    - Python-style globals (`Concore.simtime`, `Concore.delay`)
    - `ConCoreContext` for explicit state isolation
- Utilities: PID + GraphML parsing
- Observability: latency/throughput metrics collector

## Quick start

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

### Minimal controller loop (compatibility API)

```julia
using Concore

Concore.delay = 0.01

while Concore.simtime < Concore.maxtime
        while unchanged()
                ym = concore_read(1, "ym", "[0.0, 0.0]")
        end

        u = [2.0 * (100.0 - ym[1])]
        concore_write(1, "u", u; delta=0)
end
```

### Context API (recommended for new Julia code)

```julia
using Concore

ctx = ConCoreContext(delay=0.01, maxtime=200)

while ctx.simtime < ctx.maxtime
        while unchanged(ctx)
                ym = concore_read(ctx, 1, "ym", "[0.0, 0.0]")
        end

        u = [2.0 * (100.0 - ym[1])]
        concore_write(ctx, 1, "u", u; delta=0)
end
```

> Delta convention follows upstream usage: controllers typically use `delta=0`; plant models typically use `delta=1`.

## Compatibility snapshot

| Python (`concore.py`) | Julia (`Concore.jl`) |
|:---|:---|
| `concore.read(port, name, initstr)` | `concore_read(port, name, initstr)` |
| `concore.write(port, name, val, delta)` | `concore_write(port, name, val; delta)` |
| `concore.initval(str)` | `initval(str)` |
| `concore.unchanged()` | `unchanged()` |
| `concore.simtime` | `Concore.simtime` |

`concore_read` / `concore_write` are intentionally prefixed to avoid shadowing Julia `Base.read` / `Base.write`.

## Project structure

```
src/
    Concore.jl         module entry point
    protocol.jl        read/write/initval/unchanged
    parser.jl          safe wire parser
    types.jl           backend and context types
    config.jl          ports/params/maxtime
    docker.jl          Docker backend + environment detection
    shm.jl             shared-memory backend
    zmq.jl             ZeroMQ backend
    observability.jl   metrics collector
    ConcoreUtils.jl    PID + GraphML utils

benchmark/           parser, I/O, loop, SHM, memory, latency, multiprocess
test/                unit + integration suites
demo/                standalone + cross-language demos
docs/                Documenter.jl docs
standalone/          single-file distributions
```

## Tests and docs

Run tests:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Build docs:

```bash
julia --project=docs/ -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs/ docs/make.jl
```

## Benchmarks

Benchmarks are reproducible via [benchmark/](benchmark/):

```bash
julia benchmark/run_benchmarks.jl
julia benchmark/run_benchmarks.jl --with-python
```

Current runs show Julia ahead on parser/format and loop hot paths (roughly $1.7\times$ to $4\times$ in this setup).

> Numbers are prototype measurements; reproduce from the scripts above.

## Next milestones (GSoC scope)

- Remove SHM remap overhead by keeping mappings alive
- Complete standalone `concoredocker.jl` parity with Python interface
- Finalize mixed-language Docker demo nodes
- Package benchmark methodology/results as a reproducible artifact
- Upstream integration to main concore dev branch

## References

- [concore repository](https://github.com/ControlCore-Project/concore)
- [concore dev branch](https://github.com/ControlCore-Project/concore/tree/dev)
- [CONTROL-CORE paper (IEEE Access 2022)](https://doi.org/10.1109/ACCESS.2022.3161471)
- [concore documentation](https://control-core.readthedocs.io/en/latest/index.html)

## License

LGPL-2.1, aligned with upstream concore licensing.
