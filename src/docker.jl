# docker.jl -- Docker backend support for concore
#
# Inside a Docker container launched by the concore orchestrator, input and
# output directories are bind-mounted at absolute paths (/in1, /out1, etc.)
# rather than the default relative paths (./in1, ./out1).
#
# This module provides auto-detection and explicit initialization.

"""
    detect_environment() -> AbstractBackend

Auto-detect whether the process is running inside a Docker container or
locally, and return the appropriate backend.

The heuristic checks whether `/in1/` exists as a directory.  If it does,
the process is assumed to be inside a Docker container with concore
bind-mounts and [`DockerBackend`](@ref) is returned.  Otherwise,
[`FileBackend`](@ref) is returned.

This mimics the MATLAB `import_concore.m` auto-detection behaviour.

# Returns
- `DockerBackend()` if `/in1` is a directory.
- `FileBackend()` otherwise.

# Example
```julia
backend = detect_environment()
ctx = ConCoreContext(backend = backend)
```

See also: [`init_docker!`](@ref), [`DockerBackend`](@ref).
"""
function detect_environment()::AbstractBackend
    isdir("/in1") ? DockerBackend() : FileBackend()
end

# =============================================================================
# Context-based Docker init
# =============================================================================

"""
    init_docker!(ctx::ConCoreContext) -> ConCoreContext

Switch `ctx` to use [`DockerBackend`](@ref) for Docker execution.

After this call, all reads use `/in{port}/` and all writes use `/out{port}/`.

# Example
```julia
ctx = ConCoreContext()
init_docker!(ctx)
# ctx.backend is now DockerBackend()
```

See also: [`detect_environment`](@ref).
"""
function init_docker!(ctx::ConCoreContext)
    ctx.backend = DockerBackend()
    return ctx
end

# =============================================================================
# Module-global Docker init
# =============================================================================

"""
    init_docker!()

Switch the module-level backend to [`DockerBackend`](@ref).

After this call, all module-level `concore_read` / `concore_write` calls
use absolute Docker paths.
"""
function init_docker!()
    global _backend, inpath, outpath
    _backend = DockerBackend()
    inpath = "/in"
    outpath = "/out"
    return nothing
end
