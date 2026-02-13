"""
    Concore

Julia implementation of the concore file-based IPC protocol for closed-loop
peripheral neuromodulation control systems.

# Overview

The concore protocol enables closed-loop control simulations where separate
OS processes (controller, plant model, observer, …) communicate by reading
and writing small text files.  Each file contains a Python-style list:

    [simtime, value1, value2, ...]

This package provides:

- **Wire-format parser** — [`safe_parse_list`](@ref) (regex-based, no `eval`)
- **File-based read/write** — [`concore_read`](@ref), [`concore_write`](@ref)
- **Sync detection** — [`unchanged`](@ref), [`initval`](@ref)
- **Configuration** — [`load_iport!`](@ref), [`load_oport!`](@ref),
  [`load_params!`](@ref), [`tryparam`](@ref), [`default_maxtime!`](@ref)
- **Docker support** — [`DockerBackend`](@ref), [`detect_environment`](@ref)
- **Shared memory** — [`SharedMemoryBackend`](@ref), [`shm_read`](@ref),
  [`shm_write`](@ref)
- **ZeroMQ** — [`ZeroMQBackend`](@ref), [`init_zmq_port`](@ref),
  [`zmq_read`](@ref), [`zmq_write`](@ref) (requires `ZMQ.jl`)
- **Utilities** — [`ConcoreUtils`](@ref) submodule with PID controller and
  GraphML parsing

# Quick Start

```julia
using Concore

# Initialize (auto-loads port configs and params if files exist)
Concore.delay = 0.01

# Controller loop
u = initval("[0.0, 0.0]")
while Concore.simtime < Concore.maxtime
    while unchanged()
        ym = concore_read(1, "ym", "[0.0, 0.0]")
    end
    # ... compute control signal ...
    concore_write(1, "u", u; delta=0)
end
```

# Backend Selection

By default, concore uses file-based IPC with relative paths (`./in1/`, `./out1/`).
For Docker execution, use [`init_docker!`](@ref) or [`detect_environment`](@ref).
For faster same-host communication, use [`SharedMemoryBackend`](@ref).

# API Styles

The package supports two API styles:

1. **Module-global** (Python-compatible): `concore_read(1, "ym", "...")`,
   `Concore.simtime`, `Concore.delay = 0.01`
2. **Context-based** (Julia-idiomatic): `concore_read(ctx, 1, "ym", "...")`
   where `ctx` is a [`ConCoreContext`](@ref)

Both styles are fully supported and can be mixed freely.

See also: [concore project](https://github.com/ControlCore-Project/concore)
"""
module Concore

# ═══════════════════════════════════════════════════════════════════════════════
# Type definitions (backends, context)
# ═══════════════════════════════════════════════════════════════════════════════

include("types.jl")

# ═══════════════════════════════════════════════════════════════════════════════
# Module-level globals (Python API compatibility)
# ═══════════════════════════════════════════════════════════════════════════════
#
# The Python concore API exposes state as module attributes:
#     concore.simtime, concore.delay, concore.s, etc.
#
# Julia equivalents:
#     Concore.simtime, Concore.delay = 0.01, etc.
#
# These globals are the "default context" for the module-level API.  The
# context-based API (ConCoreContext) is independent and recommended for new
# code, but these globals ensure backward compatibility with existing concore
# examples and the Python interop pattern.
# ═══════════════════════════════════════════════════════════════════════════════

"""Accumulated read data for sync detection (module-global)."""
global s::String = ""

"""Previous accumulated data for sync comparison (module-global)."""
global olds::String = ""

"""Sleep interval between polling reads in seconds (module-global)."""
global delay::Float64 = 1.0

"""Cumulative file-read retry count, diagnostic (module-global)."""
global retrycount::Int = 0

"""Current simulation time (module-global)."""
global simtime::Float64 = 0.0

"""Maximum simulation time (module-global)."""
global maxtime::Int = 100

"""Input port name → number mapping (module-global)."""
global iport::Dict{String,Int} = Dict{String,Int}()

"""Output port name → number mapping (module-global)."""
global oport::Dict{String,Int} = Dict{String,Int}()

"""Runtime parameters loaded from concore.params (module-global)."""
global params::Dict{String,Any} = Dict{String,Any}()

"""Active communication backend (module-global)."""
global _backend::AbstractBackend = FileBackend()

"""Input path prefix (module-global). Set to change where reads look for files."""
global inpath::String = "./in"

"""Output path prefix (module-global). Set to change where writes place files."""
global outpath::String = "./out"

# ═══════════════════════════════════════════════════════════════════════════════
# Subfile includes (order matters: parser before config before protocol)
# ═══════════════════════════════════════════════════════════════════════════════

include("parser.jl")
include("config.jl")
include("protocol.jl")
include("docker.jl")
include("shm.jl")
include("zmq.jl")
include("observability.jl")

# ═══════════════════════════════════════════════════════════════════════════════
# ConcoreUtils submodule
# ═══════════════════════════════════════════════════════════════════════════════

include("ConcoreUtils.jl")

# ═══════════════════════════════════════════════════════════════════════════════
# Exports
# ═══════════════════════════════════════════════════════════════════════════════

# Core protocol
export concore_read, concore_write, initval, unchanged

# Configuration
export tryparam, default_maxtime!, safe_parse_list
export load_iport!, load_oport!, load_params!, concore_init!
# Backward-compat aliases (without !)
export load_iport, load_oport, load_params, default_maxtime, concore_init

# Types
export ConCoreContext, FileBackend, DockerBackend, SharedMemoryBackend
export AbstractBackend

# Docker
export detect_environment, init_docker!

# Shared memory
export shm_read, shm_write, shm_cleanup

# ZeroMQ
export ZeroMQBackend, init_zmq_port, zmq_read, zmq_write, terminate_zmq

# Observability / Metrics
export MetricsCollector, metrics_collector
export enable_metrics!, disable_metrics!, get_global_collector
export record_read!, record_write!, record_sync_wait!, record_iteration!, record_error!
export get_summary, reset_metrics!
export print_metrics, export_metrics
export timed_unchanged
export @timed_read, @timed_write

# ═══════════════════════════════════════════════════════════════════════════════
# Module-level accessors (for programmatic access to globals)
# ═══════════════════════════════════════════════════════════════════════════════

"""Return the current simulation time from the module-level global."""
get_simtime() = simtime

"""Return the polling delay from the module-level global."""
get_delay() = delay

"""Return the maximum simulation time from the module-level global."""
get_maxtime() = maxtime

"""Return the retry count from the module-level global."""
get_retrycount() = retrycount

"""Return the input port mapping from the module-level global."""
get_iport() = iport

"""Return the output port mapping from the module-level global."""
get_oport() = oport

"""Return the parameters from the module-level global."""
get_params() = params

"""Set the simulation time in the module-level global."""
set_simtime!(v::Real) = (global simtime; simtime = Float64(v))

"""Set the polling delay in the module-level global."""
set_delay!(v::Real) = (global delay; delay = Float64(v))

"""Set the maximum simulation time in the module-level global."""
set_maxtime!(v::Integer) = (global maxtime; maxtime = Int(v))

# ═══════════════════════════════════════════════════════════════════════════════
# Backward-compatible aliases (without `!` suffix)
# ═══════════════════════════════════════════════════════════════════════════════
# The original API used `load_iport()`, `load_oport()`, `load_params()`,
# `default_maxtime()`, and `concore_init()` without `!`.  These aliases
# preserve backward compatibility with existing examples and scripts.

"""Backward-compatible alias for [`load_iport!`](@ref)."""
const load_iport = load_iport!

"""Backward-compatible alias for [`load_oport!`](@ref)."""
const load_oport = load_oport!

"""Backward-compatible alias for [`load_params!`](@ref)."""
const load_params = load_params!

"""Backward-compatible alias for [`default_maxtime!`](@ref)."""
const default_maxtime = default_maxtime!

"""Backward-compatible alias for [`concore_init!`](@ref)."""
const concore_init = concore_init!

# ═══════════════════════════════════════════════════════════════════════════════
# Initialization
# ═══════════════════════════════════════════════════════════════════════════════

function __init__()
    # Auto-load configuration if files exist in the working directory.
    # Failures are expected (e.g., running tests, REPL without a study)
    # and silently ignored.
    try
        concore_init!()
    catch e
        @debug "Concore.__init__: auto-init skipped" exception=(e, catch_backtrace())
    end
end

end # module Concore
