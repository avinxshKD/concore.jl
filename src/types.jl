# types.jl -- Type definitions for the Concore protocol
#
# Defines the backend hierarchy and the mutable ConCoreContext that holds
# all per-node state.  Helper path-construction functions live here too
# because they depend only on the types.

# =============================================================================
# Communication Backends
# =============================================================================

"""
    AbstractBackend

Abstract supertype for concore communication backends.

The concore protocol is transport-agnostic: nodes exchange data through a
backend that knows how to read/write signal files.  Concrete subtypes select
the transport mechanism.

See also: [`FileBackend`](@ref), [`DockerBackend`](@ref), [`SharedMemoryBackend`](@ref).
"""
abstract type AbstractBackend end

"""
    FileBackend <: AbstractBackend

File-based IPC backend (the default).

Reads from `./in{port}/{name}` and writes to `./out{port}/{name}`, where
paths are relative to the working directory of the concore study.  This is
the standard backend used by the Python, C++, and MATLAB concore
implementations for local execution.
"""
struct FileBackend <: AbstractBackend end

"""
    DockerBackend <: AbstractBackend

Docker file-based backend.

Uses **absolute** paths `/in{port}/{name}` and `/out{port}/{name}` that are
bind-mounted into the container by the concore orchestrator.  Functionally
identical to [`FileBackend`](@ref) but rooted at `/` instead of `./`.

See also: [`detect_environment`](@ref), [`init_docker!`](@ref).
"""
struct DockerBackend <: AbstractBackend end

"""
    SharedMemoryBackend <: AbstractBackend

Shared-memory backend using memory-mapped files (`Mmap.jl`).

Creates fixed-size memory-mapped files at the standard concore paths.  Data
is written in the same wire format as the file backends (for compatibility)
but avoids filesystem buffering overhead.

# Fields
- `segment_size::Int` — size of each mapped region in bytes (default 4096).

# Example
```julia
ctx = ConCoreContext(backend = SharedMemoryBackend(8192))
```
"""
struct SharedMemoryBackend <: AbstractBackend
    segment_size::Int
end

SharedMemoryBackend() = SharedMemoryBackend(4096)

# =============================================================================
# ConCoreContext
# =============================================================================

"""
    ConCoreContext

Holds all mutable state for a single concore node.

Each node in a concore study (controller, plant, observer, …) maintains its
own context.  The module also provides a set of module-level globals that
mirror the default context for backward compatibility with the Python-style
API (`Concore.simtime`, `Concore.delay`, etc.).

# Fields
| Field         | Type                  | Description                                    |
|:------------- |:--------------------- |:---------------------------------------------- |
| `s`           | `String`              | Accumulated read data for sync detection        |
| `olds`        | `String`              | Previous accumulated data for sync comparison   |
| `delay`       | `Float64`             | Sleep interval between polling reads (seconds)  |
| `retrycount`  | `Int`                 | Cumulative file-read retry count (diagnostic)   |
| `simtime`     | `Float64`             | Current simulation time                         |
| `maxtime`     | `Int`                 | Maximum simulation time (loop termination)      |
| `iport`       | `Dict{String,Int}`    | Input port name → number mapping                |
| `oport`       | `Dict{String,Int}`    | Output port name → number mapping               |
| `params`      | `Dict{String,Any}`    | Parameters loaded from `concore.params`          |
| `backend`     | `AbstractBackend`     | Communication backend                           |

# Constructor
```julia
ConCoreContext(; backend=FileBackend(), delay=1.0, maxtime=100)
```

# Example
```julia
ctx = ConCoreContext(delay = 0.01, maxtime = 50)
```
"""
mutable struct ConCoreContext
    s::String
    olds::String
    delay::Float64
    retrycount::Int
    simtime::Float64
    maxtime::Int
    iport::Dict{String,Int}
    oport::Dict{String,Int}
    params::Dict{String,Any}
    backend::AbstractBackend
end

function ConCoreContext(;
    backend::AbstractBackend = FileBackend(),
    delay::Float64 = 1.0,
    maxtime::Int = 100,
)
    ConCoreContext(
        "",          # s
        "",          # olds
        delay,       # delay
        0,           # retrycount
        0.0,         # simtime
        maxtime,     # maxtime
        Dict{String,Int}(),   # iport
        Dict{String,Int}(),   # oport
        Dict{String,Any}(),   # params
        backend,
    )
end

function Base.show(io::IO, ctx::ConCoreContext)
    print(io, "ConCoreContext(backend=", typeof(ctx.backend),
          ", simtime=", ctx.simtime,
          ", maxtime=", ctx.maxtime,
          ", delay=", ctx.delay,
          ", iports=", length(ctx.iport),
          ", oports=", length(ctx.oport), ")")
end

# =============================================================================
# Path helpers
# =============================================================================
# NOTE: These are named `_backend_inpath` / `_backend_outpath` (internal) to
# avoid clashing with the module-level `inpath::String` / `outpath::String`
# globals that the Python-compatible API exposes (e.g. `Concore.inpath = "..."`).

"""
    _backend_inpath(backend::AbstractBackend) -> String

Return the input path prefix for the given backend.

| Backend                | Prefix   |
|:---------------------- |:-------- |
| `FileBackend`          | `"./in"` |
| `DockerBackend`        | `"/in"`  |
| `SharedMemoryBackend`  | `"./in"` |

The full input directory is formed by concatenating this prefix with the port
number: `_backend_inpath(backend) * string(port)` → e.g. `"./in1"`.
"""
_backend_inpath(::FileBackend) = "./in"
_backend_inpath(::DockerBackend) = "/in"
_backend_inpath(::SharedMemoryBackend) = "./in"   # config files still live on disk

"""
    _backend_outpath(backend::AbstractBackend) -> String

Return the output path prefix for the given backend.

| Backend                | Prefix    |
|:---------------------- |:--------- |
| `FileBackend`          | `"./out"` |
| `DockerBackend`        | `"/out"`  |
| `SharedMemoryBackend`  | `"./out"` |
"""
_backend_outpath(::FileBackend) = "./out"
_backend_outpath(::DockerBackend) = "/out"
_backend_outpath(::SharedMemoryBackend) = "./out"

"""
    indir(ctx::ConCoreContext, port::Int) -> String

Full input directory path for port `port`.

# Example
```jldoctest
julia> ctx = Concore.ConCoreContext();

julia> Concore.indir(ctx, 1)
"./in1"
```
"""
indir(ctx::ConCoreContext, port::Int) = _backend_inpath(ctx.backend) * string(port)

"""
    outdir(ctx::ConCoreContext, port::Int) -> String

Full output directory path for port `port`.

# Example
```jldoctest
julia> ctx = Concore.ConCoreContext();

julia> Concore.outdir(ctx, 1)
"./out1"
```
"""
outdir(ctx::ConCoreContext, port::Int) = _backend_outpath(ctx.backend) * string(port)
