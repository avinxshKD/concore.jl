# shm.jl -- Shared-memory backend using memory-mapped files
#
# The C++ concore implementation uses System V shared memory for fast IPC.
# Julia does not have a built-in POSIX shm API, but it does have `Mmap.jl`
# which memory-maps regular files.  This module provides an Mmap-based
# shared-memory backend that:
#
#   • Creates fixed-size memory-mapped files at the standard concore paths
#   • Uses the same wire format as the file backends (for cross-language compat)
#   • Avoids filesystem buffering overhead for same-host communication
#
# The approach is pragmatic: we memory-map files at the same paths the file
# backend would use, so the directory layout is unchanged and other processes
# can still read/write with plain file I/O.

using Mmap

# =============================================================================
# Segment registry
# =============================================================================

"""
    _shm_segments

Global registry of open memory-mapped file streams, keyed by path.

Streams are kept open for the lifetime of the process to avoid repeated
open/close overhead.  The `atexit` hook in [`_register_shm_cleanup`](@ref)
closes them all on exit.
"""
const _shm_segments = Dict{String, IOStream}()

# Track whether the atexit hook has been registered
const _shm_cleanup_registered = Ref(false)

"""
    _register_shm_cleanup()

Register an `atexit` hook to close all shared-memory file handles.
Idempotent — safe to call multiple times.
"""
function _register_shm_cleanup()
    if !_shm_cleanup_registered[]
        atexit(shm_cleanup)
        _shm_cleanup_registered[] = true
    end
end

"""
    _get_or_create_segment(path::AbstractString, size::Int) -> IOStream

Return an open `IOStream` for the memory-mapped file at `path`, creating
the file (and parent directories) if needed.

The file is pre-allocated to `size` bytes and zero-filled on first creation.
Subsequent calls return the cached stream from [`_shm_segments`](@ref).
"""
function _get_or_create_segment(path::AbstractString, size::Int)::IOStream
    if haskey(_shm_segments, path) && isopen(_shm_segments[path])
        return _shm_segments[path]
    end

    _register_shm_cleanup()

    mkpath(dirname(path))

    # Create or open the file with read+write
    if !isfile(path)
        io = open(path, "w+")
        # Pre-allocate to segment_size
        write(io, zeros(UInt8, size))
        seekstart(io)
    else
        io = open(path, "r+")
        # Ensure file is at least `size` bytes
        fsize = filesize(path)
        if fsize < size
            seekend(io)
            write(io, zeros(UInt8, size - fsize))
            seekstart(io)
        end
    end

    _shm_segments[path] = io
    return io
end

# =============================================================================
# Shared-memory read
# =============================================================================

"""
    shm_read(ctx::ConCoreContext, port::Int, name::AbstractString, initstr::AbstractString) -> Vector{Float64}

Read data via a memory-mapped file at `{inpath}{port}/{name}`.

The function maps the file into memory, reads the wire-format string up to
the first null byte (or end of mapped region), and parses it.  If the
mapped region is empty or unreadable, `initstr` is used as fallback.

This is functionally equivalent to [`concore_read`](@ref) but avoids the
filesystem read(2) overhead by using an `mmap`ed region.

# Arguments
- `ctx::ConCoreContext` — context with `SharedMemoryBackend` backend.
- `port::Int` — port number.
- `name::AbstractString` — signal name.
- `initstr::AbstractString` — fallback wire-format string.

# Returns
`Vector{Float64}` — data values (without simtime), same as `concore_read`.
"""
function shm_read(
    ctx::ConCoreContext,
    port::Int,
    name::AbstractString,
    initstr::AbstractString,
)::Vector{Float64}
    backend = ctx.backend
    if !(backend isa SharedMemoryBackend)
        # Fall back to standard file read
        return concore_read(ctx, port, name, initstr)
    end

    sleep(ctx.delay)

    filepath = joinpath(indir(ctx, port), name)
    ins = ""

    try
        io = _get_or_create_segment(filepath, backend.segment_size)
        seekstart(io)
        buf = Mmap.mmap(io, Vector{UInt8}, backend.segment_size)

        # Find the end of meaningful data (first null byte or end)
        nullpos = findfirst(iszero, buf)
        data_end = nullpos === nothing ? length(buf) : nullpos - 1

        if data_end > 0
            ins = String(buf[1:data_end])
        end

        # Unmap
        finalize(buf)
    catch e
        @debug "shm_read: mmap failed, using initstr" filepath exception=(e, catch_backtrace())
        ins = initstr
    end

    # Retry if empty
    attempts = 0
    while isempty(strip(ins)) && attempts < 5
        sleep(ctx.delay)
        try
            io = _get_or_create_segment(filepath, backend.segment_size)
            seekstart(io)
            buf = Mmap.mmap(io, Vector{UInt8}, backend.segment_size)
            nullpos = findfirst(iszero, buf)
            data_end = nullpos === nothing ? length(buf) : nullpos - 1
            if data_end > 0
                ins = String(buf[1:data_end])
            end
            finalize(buf)
        catch e
            @debug "shm_read: retry mmap failed" filepath attempt=attempts exception=(e, catch_backtrace())
        end
        attempts += 1
        ctx.retrycount += 1
    end

    if isempty(strip(ins))
        ins = initstr
    end

    ctx.s = _cap_s(ctx.s, ins)

    val = safe_parse_list(ins)
    ctx.simtime = max(ctx.simtime, val[1])
    return val[2:end]
end

# =============================================================================
# Shared-memory write
# =============================================================================

"""
    shm_write(ctx::ConCoreContext, port::Int, name::AbstractString, val::Vector{Float64}; delta::Int=0)

Write data via a memory-mapped file at `{outpath}{port}/{name}`.

Formats the data as `[simtime + delta, val...]` in wire format, writes it
into the mapped region, and null-terminates.  This is functionally equivalent
to [`concore_write`](@ref) but uses `mmap` to avoid filesystem write overhead.

# Arguments
- `ctx::ConCoreContext` — context with `SharedMemoryBackend` backend.
- `port::Int` — port number.
- `name::AbstractString` — signal name.
- `val::Vector{Float64}` — data values.
- `delta::Int=0` — time increment added to simtime.
"""
function shm_write(
    ctx::ConCoreContext,
    port::Int,
    name::AbstractString,
    val::Vector{Float64};
    delta::Int = 0,
)
    backend = ctx.backend
    if !(backend isa SharedMemoryBackend)
        # Fall back to standard file write
        concore_write(ctx, port, name, val; delta=delta)
        return nothing
    end

    filepath = joinpath(outdir(ctx, port), name)
    outval = vcat(ctx.simtime + delta, val)
    wire = _format_wire(outval)

    try
        io = _get_or_create_segment(filepath, backend.segment_size)
        seekstart(io)
        buf = Mmap.mmap(io, Vector{UInt8}, backend.segment_size)

        wire_bytes = Vector{UInt8}(wire)
        n = min(length(wire_bytes), backend.segment_size - 1)

        # Write data
        buf[1:n] .= wire_bytes[1:n]
        # Null-terminate to mark end of data
        buf[n+1] = 0x00
        # Zero the rest to prevent stale data leaking
        if n + 2 <= backend.segment_size
            buf[n+2:end] .= 0x00
        end

        # Force flush
        Mmap.sync!(buf)
        finalize(buf)
    catch e
        @debug "shm_write: mmap failed, falling back to file write" filepath exception=(e, catch_backtrace())
        # Fall back to regular file write
        mkpath(dirname(filepath))
        open(filepath, "w") do f
            write(f, wire)
        end
    end

    ctx.simtime += delta
    @debug "shm_write" filepath wire simtime=ctx.simtime
    return nothing
end

# =============================================================================
# Cleanup
# =============================================================================

"""
    shm_cleanup()

Close all open shared-memory file handles and clear the segment registry.

Called automatically via an `atexit` hook.  Can also be called manually to
release resources early (e.g., between test runs).

# Example
```julia
shm_cleanup()  # close all mmap handles
```
"""
function shm_cleanup()
    for (path, io) in _shm_segments
        try
            isopen(io) && close(io)
        catch e
            @debug "shm_cleanup: failed to close" path exception=(e, catch_backtrace())
        end
    end
    empty!(_shm_segments)
    @debug "shm_cleanup: released all segments"
    return nothing
end
