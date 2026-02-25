# Getting Started

This guide walks you through installing Concore.jl and writing your first closed-loop control system.

## Installation

### From GitHub (recommended during development)

```julia
using Pkg
Pkg.add(url="https://github.com/ControlCore-Project/concore", subdir="concore-jl")
```

### For development

```julia
using Pkg
Pkg.develop(path="/path/to/concore-jl")
```

### Verify installation

```julia
using Concore
println("Concore.jl loaded successfully")
```

## Core Concepts

### The concore Protocol

The concore protocol connects **nodes** (separate processes) through file-based IPC. Each node:

1. **Reads** input data from files in `./in{port}/` directories
2. **Processes** the data (e.g., applies a control law)
3. **Writes** output data to files in `./out{port}/` directories

A study runner (typically `concore.py`) orchestrates the directory structure and launches nodes.

### Simulation Time

Every message in concore carries a **simulation timestamp** as its first element:

```
[simtime, value1, value2, ...]
```

Simulation time increases monotonically. The `delta` parameter in `concore_write` controls how much time advances per write. The simulation runs until `simtime >= maxtime`.

## Basic Usage

### Initializing Values

Use `initval` to parse an initial value string and set the starting simulation time:

```julia
using Concore

# Parse initial values -- simtime is extracted, remaining values returned
y = initval("[0.0, 1.0, 2.0]")   # y == [1.0, 2.0], simtime set to 0.0
```

### Reading Data

`concore_read` reads data from an input port. It blocks (polls with delay) until new data appears:

```julia
# Read from port 1, file named "y", with fallback initial value
y = concore_read(1, "y", "[0.0, 0.0]")
```

The third argument is a fallback string used if the file does not yet exist.

### Writing Data

`concore_write` writes data to an output port:

```julia
# Write control signal to port 1, file named "u"
u = [1.5, -0.3]
concore_write(1, "u", u; delta=1)
```

The `delta` keyword advances simulation time by the given amount.

### Checking for Changes

`unchanged()` returns `true` if no new data has been read since the last call. Use it in the standard polling loop:

```julia
while Concore.simtime < Concore.maxtime
    while unchanged()
        y = concore_read(1, "y", "[0.0, 0.0]")
    end

    # Process y, compute u
    u = [-2.0 * y[1]]
    concore_write(1, "u", u; delta=1)
end
```

## Controller Pattern

A typical **controller** node reads a reference signal and a measurement, computes a control action, and writes it out:

```julia
using Concore

# Initial values
r = initval("[0.0, 1.0]")    # reference/setpoint
y = initval("[0.0, 0.0]")    # measurement

Kp = 2.0   # proportional gain
Ki = 0.1   # integral gain
integral = 0.0

while Concore.simtime < Concore.maxtime
    while unchanged()
        r = concore_read(1, "refs", "[0.0, 1.0]")
        y = concore_read(1, "y", "[0.0, 0.0]")
    end

    e = r[1] - y[1]
    integral += e
    u = [Kp * e + Ki * integral]

    concore_write(1, "u", u; delta=1)
end
```

## Plant Model Pattern

A **plant** node reads a control signal and simulates the system dynamics:

```julia
using Concore

# Initial state
u = initval("[0.0, 0.0]")
x = 0.0    # internal state

# Simple first-order plant: x[k+1] = 0.9*x[k] + 0.1*u[k]
while Concore.simtime < Concore.maxtime
    while unchanged()
        u = concore_read(1, "u", "[0.0, 0.0]")
    end

    x = 0.9 * x + 0.1 * u[1]
    y = [x]

    concore_write(1, "y", y; delta=1)
end
```

## Using Parameters

Parameters are loaded from `concore.params` files. Access them with `tryparam`:

```julia
using Concore

# Get parameter "Kp" with default value 1.0
Kp = tryparam("Kp", 1.0)

# Get string parameter
mode = tryparam("mode", "auto")
```

Parameters can be set in two formats:

**Python dict format:**
```
{'Kp': 2.0, 'Ki': 0.1, 'mode': 'auto'}
```

**Key-value format:**
```
Kp=2.0;Ki=0.1;mode=auto
```

## Delta Convention

The `delta` parameter in `concore_write` controls simulation time advancement:

- `delta=0` (default): Write without advancing time. Used when a node writes multiple outputs per timestep.
- `delta=1`: Advance simulation time by 1 after writing. The standard choice for single-output nodes.

**Important**: Only one node in a loop should advance time per cycle. If both controller and plant use `delta=1`, time advances by 2 per cycle.

Typical convention:
- Controller: `concore_write(1, "u", u; delta=1)` -- advances time
- Plant: `concore_write(1, "y", y; delta=0)` -- does not advance time

## Running Examples

### Standalone test

```bash
cd concore-jl/examples
julia controller.jl &
julia plant.jl &
wait
```

### With the concore study runner

```bash
# From the concore project root
python concore.py study.graphml
```

The study runner reads a GraphML file describing the control loop topology and launches all nodes (potentially in different languages) with the correct directory mappings.

## Next Steps

- [API Reference](@ref) -- Complete function documentation
- [Backends](@ref) -- Learn about Docker and shared memory backends
- [Cross-Language Interop](@ref) -- Test Julia nodes with Python/C++ nodes
