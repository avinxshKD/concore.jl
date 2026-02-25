# Concore.jl

*Julia implementation of the concore protocol for closed-loop peripheral neuromodulation control systems.*

[![CI](https://github.com/ControlCore-Project/concore/actions/workflows/CI.yml/badge.svg)](https://github.com/ControlCore-Project/concore/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/ControlCore-Project/concore/branch/main/graph/badge.svg)](https://codecov.io/gh/ControlCore-Project/concore)

## Overview

Concore.jl is the Julia reference implementation of the [CONTROL-CORE](https://github.com/ControlCore-Project/concore) file-based inter-process communication protocol. It enables Julia programs to participate as nodes in closed-loop neuromodulation studies alongside nodes written in Python, C++, or any other language that implements the concore wire format.

The concore protocol is designed for **closed-loop control systems** where:

- A **controller** reads sensor data and computes control signals
- A **plant** (physical system or simulation) receives control signals and produces sensor readings
- Multiple nodes communicate through a shared file-based IPC mechanism
- Nodes can be written in different languages and run in separate processes or Docker containers

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/ControlCore-Project/concore", subdir="concore-jl")
```

Or in the Julia REPL package mode:

```
pkg> add https://github.com/ControlCore-Project/concore#main:concore-jl
```

## Quick Start

Here is a minimal proportional controller that reads a setpoint error and writes a control signal:

```julia
using Concore

# Initialize with default values
r = initval("[0.0, 0.5]")   # [simtime, setpoint]
y = initval("[0.0, 0.0]")   # [simtime, measurement]

Kp = 2.0  # proportional gain

while Concore.simtime < Concore.maxtime
    while unchanged()
        r = concore_read(1, "refs", "[0.0, 0.5]")
        y = concore_read(1, "y", "[0.0, 0.0]")
    end

    # Proportional control law
    e = r[1] - y[1]
    u = [Kp * e]

    concore_write(1, "u", u; delta=1)
end
```

## API Mapping

Concore.jl mirrors the Python and C++ concore APIs. The following table maps equivalent functions:

| Python | C++ | Julia | Description |
|--------|-----|-------|-------------|
| `concore.read(port, name, init)` | `concore_read(port, name, init)` | `concore_read(port, name, init)` | Read data from input port |
| `concore.write(port, name, val)` | `concore_write(port, name, val)` | `concore_write(port, name, val)` | Write data to output port |
| `concore.initval(s)` | `concore_initval(s)` | `initval(s)` | Parse initial value string |
| `concore.unchanged()` | `concore_unchanged()` | `unchanged()` | Check if data changed |
| `concore.default_maxtime(n)` | `concore_default_maxtime(n)` | `default_maxtime!(n)` | Set max simulation time |
| `concore.tryparam(k, d)` | `concore_tryparam(k, d)` | `tryparam(k, d)` | Get parameter with default |
| `concore.delay` | `concore_delay` | `Concore.delay` | Polling delay (seconds) |
| `concore.simtime` | `concore_simtime` | `Concore.simtime` | Current simulation time |
| `concore.maxtime` | `concore_maxtime` | `Concore.maxtime` | Maximum simulation time |

## Wire Format

All concore nodes communicate using a simple text-based wire format:

```
[simtime, value1, value2, ...]
```

- **simtime**: A floating-point simulation timestamp (monotonically increasing)
- **values**: One or more floating-point data values

Examples:
```
[0.0, 1.5, 2.3]
[5.0, 0.0]
[12.0, -3.14, 2.718, 1.414]
```

The parser (`safe_parse_list`) handles numpy annotations (`np.float64(1.5)`), Python booleans (`True`/`False`), and `None` values for cross-language compatibility.

## Package Structure

```
concore-jl/
  Project.toml          # Package metadata and dependencies
  src/
    Concore.jl          # Main module: protocol state and I/O
    types.jl            # Type definitions (ConCoreContext, backends)
    parser.jl           # Wire format parser (safe_parse_list)
    ConcoreUtils.jl     # Optional utilities (PID controller, GraphML)
  test/
    runtests.jl         # Test suite entry point
  examples/
    controller.jl       # Example proportional controller
    plant.jl            # Example plant model
  docs/
    make.jl             # Documenter.jl build script
    src/                # Documentation source files
```

## Further Reading

- [Getting Started Guide](@ref) -- Step-by-step tutorial
- [API Reference](@ref) -- Complete function documentation
- [Backends](@ref) -- File, Docker, and shared memory backends
- [Cross-Language Interop](@ref) -- Wire format and multi-language testing
- [Contributing](@ref) -- How to contribute to Concore.jl
- [CONTROL-CORE Project](https://github.com/ControlCore-Project/concore) -- Parent project
