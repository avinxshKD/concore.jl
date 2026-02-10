# protocol.jl -- Core concore read / write / sync protocol
#
# This is the heart of the concore file-based IPC protocol.
#
# Wire format:  [simtime, val1, val2, ...]
# Path layout:  {in,out}{port}/{name}   e.g. ./in1/ym, ./out1/u
#
# Every function has two overloads:
#   1. Context-based:  func(ctx::ConCoreContext, ...)
#   2. Module-global:  func(...)            -- Python API compat
#
# The module-global versions use the typed globals defined in Concore.jl.

# Maximum accumulated `s` string length.  The sync detection mechanism
# appends every raw read to `s`; without a cap this grows without bound
# for long-running simulations.  We keep the most recent portion to ensure
# `unchanged()` still works correctly.
const _S_MAX_LEN = 65_536

"""
    _cap_s(current::AbstractString, addition::AbstractString) -> String

Append `addition` to `current` and truncate from the front if the combined
length exceeds `$(_S_MAX_LEN)` characters.

This prevents unbounded memory growth in long simulations while preserving
enough tail data for `unchanged()` to detect fresh reads.
"""
function _cap_s(current::AbstractString, addition::AbstractString)::String
    combined = current * addition
    len = length(combined)
    if len > _S_MAX_LEN
        # Keep only the tail; this is safe because unchanged() only checks
        # equality between `s` and `olds`, not positional content.
        return combined[end - _S_MAX_LEN + 1:end]
    end
    return combined
end

# =============================================================================
# Format helper (wire-format compatible output)
# =============================================================================

"""
    _format_wire(vals::Vector{Float64}) -> String

Format a `Vector{Float64}` as a concore wire-format string.

The output is exactly compatible with the Python concore implementation:
integer-valued floats print with a `.0` suffix; other values are rounded
to 15 significant digits to suppress IEEE 754 noise.

# Examples
```jldoctest
julia> Concore._format_wire([5.0, 42.0, 3.14])
"[5.0, 42.0, 3.14]"

julia> Concore._format_wire([0.0])
"[0.0]"
```
"""
function _format_wire(vals::Vector{Float64})::String
    buf = IOBuffer()
    print(buf, "[")
    for (i, v) in enumerate(vals)
        i > 1 && print(buf, ", ")
        if isinteger(v) && isfinite(v) && abs(v) < 1e15
            print(buf, string(Int(v)), ".0")
        else
            print(buf, round(v; sigdigits=15))
        end
    end
    print(buf, "]")
    return String(take!(buf))
end

# =============================================================================
# concore_read  (context-based)
# =============================================================================

"""
    concore_read(ctx::ConCoreContext, port::Int, name::AbstractString, initstr::AbstractString) -> Vector{Float64}

Read data from the input port file `{inpath}{port}/{name}`.

Implements the concore polling protocol:
1. Sleep for `ctx.delay` seconds to yield to writers.
2. Read the file contents at the computed path.
3. Retry up to 5 times (with `ctx.delay` sleeps) if the file is empty.
4. Parse the wire format `[simtime, v1, v2, …]`.
5. Update `ctx.simtime` to `max(current, file_simtime)`.
6. Append raw file content to `ctx.s` for sync detection.
7. Return the data portion (everything after simtime).

Falls back to `initstr` if the file does not exist or is unreadable.

# Arguments
- `ctx::ConCoreContext` — node context holding state and backend.
- `port::Int` — port number (maps to directory suffix, e.g. port 1 → `in1/`).
- `name::AbstractString` — signal name (filename within the port directory).
- `initstr::AbstractString` — fallback value in wire format if file is unavailable.

# Returns
`Vector{Float64}` containing the data values (without simtime).

# Example
```julia
ctx = ConCoreContext(delay = 0.01)
while unchanged(ctx)
    ym = concore_read(ctx, 1, "ym", "[0.0, 0.0]")
end
```

See also: [`concore_write`](@ref), [`unchanged`](@ref), [`initval`](@ref).
"""
function concore_read(
    ctx::ConCoreContext,
    port::Int,
    name::AbstractString,
    initstr::AbstractString,
)::Vector{Float64}
    sleep(ctx.delay)

    filepath = joinpath(indir(ctx, port), name)

    ins = ""
    try
        ins = read(filepath, String)
    catch e
        @debug "concore_read: file read failed, using initstr" filepath exception=(e, catch_backtrace())
        ins = initstr
    end

    # Retry if file was empty (writer may not have flushed yet)
    attempts = 0
    while isempty(ins) && attempts < 5
        sleep(ctx.delay)
        try
            ins = read(filepath, String)
        catch e
            @debug "concore_read: retry failed" filepath attempt=attempts exception=(e, catch_backtrace())
        end
        attempts += 1
        ctx.retrycount += 1
    end

    if isempty(ins)
        ins = initstr
    end

    # Accumulate for sync detection, capped to prevent unbounded growth
    ctx.s = _cap_s(ctx.s, ins)

    val = safe_parse_list(ins)
    ctx.simtime = max(ctx.simtime, val[1])
    return val[2:end]
end

# =============================================================================
# concore_read  (module-global)
# =============================================================================

"""
    concore_read(port::Int, name::AbstractString, initstr::AbstractString) -> Vector{Float64}

Read data from port — module-global version for Python API compatibility.

Operates on the module-level globals (`Concore.simtime`, `Concore.s`, etc.)
rather than a context object.  Otherwise identical to the context-based
overload.

# Example
```julia
using Concore
Concore.delay = 0.01
while unchanged()
    ym = concore_read(1, "ym", "[0.0, 0.0]")
end
```

See also: [`concore_read(::ConCoreContext, ...)`](@ref).
"""
function concore_read(
    port::Int,
    name::AbstractString,
    initstr::AbstractString,
)::Vector{Float64}
    global s, simtime, retrycount

    sleep(delay)

    filepath = joinpath(inpath * string(port), name)

    ins = ""
    try
        ins = read(filepath, String)
    catch e
        @debug "concore_read: file read failed, using initstr" filepath exception=(e, catch_backtrace())
        ins = initstr
    end

    # Retry if file was empty
    attempts = 0
    while isempty(ins) && attempts < 5
        sleep(delay)
        try
            ins = read(filepath, String)
        catch e
            @debug "concore_read: retry failed" filepath attempt=attempts exception=(e, catch_backtrace())
        end
        attempts += 1
        retrycount += 1
    end

    if isempty(ins)
        ins = initstr
    end

    # Accumulate for sync detection, capped to prevent unbounded growth
    s = _cap_s(s, ins)

    val = safe_parse_list(ins)
    simtime = max(simtime, val[1])
    return val[2:end]
end

# =============================================================================
# concore_write  (context-based, Vector{Float64})
# =============================================================================

"""
    concore_write(ctx::ConCoreContext, port::Int, name::AbstractString, val::Vector{Float64}; delta::Int=0)

Write data to the output port file `{outpath}{port}/{name}`.

The written wire format is `[simtime + delta, val...]`.  Controller nodes
typically write with `delta=0`; plant nodes write with `delta=1` to advance
the simulation clock.

The output directory is created automatically if it does not exist.

# Arguments
- `ctx::ConCoreContext` — node context.
- `port::Int` — port number.
- `name::AbstractString` — signal name.
- `val::Vector{Float64}` — data values to write.
- `delta::Int=0` — time increment added to simtime in the output.

# Wire Format
```
[simtime+delta, val1, val2, ...]
```
Integer-valued floats are formatted with `.0` suffix for Python compatibility.

# Example
```julia
concore_write(ctx, 1, "u", [42.0, 3.14]; delta=0)
# writes e.g. "[5.0, 42.0, 3.14]" if simtime is 5.0
```

See also: [`concore_read`](@ref).
"""
function concore_write(
    ctx::ConCoreContext,
    port::Int,
    name::AbstractString,
    val::Vector{Float64};
    delta::Int = 0,
)
    filepath = joinpath(outdir(ctx, port), name)
    mkpath(dirname(filepath))

    outval = vcat(ctx.simtime + delta, val)
    wire = _format_wire(outval)

    open(filepath, "w") do f
        write(f, wire)
    end

    ctx.simtime += delta
    @debug "concore_write" filepath wire simtime=ctx.simtime
    return nothing
end

# =============================================================================
# concore_write  (context-based, raw String)
# =============================================================================

"""
    concore_write(ctx::ConCoreContext, port::Int, name::AbstractString, val::AbstractString; delta::Int=0)

Write a raw string to the output port file.

Used for non-numeric data or pre-formatted wire strings.  Sleeps for
`2 * ctx.delay` before writing to give readers time to finish.
"""
function concore_write(
    ctx::ConCoreContext,
    port::Int,
    name::AbstractString,
    val::AbstractString;
    delta::Int = 0,
)
    sleep(2 * ctx.delay)
    filepath = joinpath(outdir(ctx, port), name)
    mkpath(dirname(filepath))
    open(filepath, "w") do f
        write(f, val)
    end
    @debug "concore_write(raw)" filepath length=length(val)
    return nothing
end

# =============================================================================
# concore_write  (module-global, Vector{Float64})
# =============================================================================

"""
    concore_write(port::Int, name::AbstractString, val::Vector{Float64}; delta::Int=0)

Write data to port — module-global version for Python API compatibility.

# Example
```julia
concore_write(1, "u", [42.0, 3.14]; delta=0)
```
"""
function concore_write(
    port::Int,
    name::AbstractString,
    val::Vector{Float64};
    delta::Int = 0,
)
    global simtime

    filepath = joinpath(outpath * string(port), name)
    mkpath(dirname(filepath))

    outval = vcat(simtime + delta, val)
    wire = _format_wire(outval)

    open(filepath, "w") do f
        write(f, wire)
    end

    simtime += delta
    @debug "concore_write" filepath wire simtime
    return nothing
end

# =============================================================================
# concore_write  (module-global, raw String)
# =============================================================================

"""
    concore_write(port::Int, name::AbstractString, val::AbstractString; delta::Int=0)

Write a raw string — module-global version.
"""
function concore_write(
    port::Int,
    name::AbstractString,
    val::AbstractString;
    delta::Int = 0,
)
    sleep(2 * delay)
    filepath = joinpath(outpath * string(port), name)
    mkpath(dirname(filepath))
    open(filepath, "w") do f
        write(f, val)
    end
    return nothing
end

# =============================================================================
# initval
# =============================================================================

"""
    initval(ctx::ConCoreContext, simtime_val::AbstractString) -> Vector{Float64}

Parse an initial value string, set context simtime, return data portion.

The input is a wire-format string `[simtime, v1, v2, ...]`.  The first
element sets `ctx.simtime`; the remaining elements are returned.

# Example
```julia
ctx = ConCoreContext()
u = initval(ctx, "[0.0, 1.5, 2.5]")
# u == [1.5, 2.5], ctx.simtime == 0.0
```

See also: [`safe_parse_list`](@ref).
"""
function initval(ctx::ConCoreContext, simtime_val::AbstractString)::Vector{Float64}
    val = safe_parse_list(simtime_val)
    ctx.simtime = val[1]
    return val[2:end]
end

"""
    initval(simtime_val::AbstractString) -> Vector{Float64}

Parse initial value — module-global version.

# Example
```julia
u = initval("[0.0, 1.5, 2.5]")
# Concore.simtime is now 0.0, u == [1.5, 2.5]
```
"""
function initval(simtime_val::AbstractString)::Vector{Float64}
    global simtime
    val = safe_parse_list(simtime_val)
    simtime = val[1]
    return val[2:end]
end

# =============================================================================
# unchanged  (sync detection)
# =============================================================================

"""
    unchanged(ctx::ConCoreContext) -> Bool

Return `true` if no new data has been read since the last call.

The standard concore sync loop is:
```julia
while unchanged(ctx)
    ym = concore_read(ctx, 1, "ym", "[0.0, 0.0]")
end
# ym now contains fresh data — proceed with computation
```

# Algorithm
- If `ctx.s == ctx.olds`, no new data was appended by `concore_read` →
  reset `ctx.s` to `""` and return `true` (unchanged, keep waiting).
- Otherwise, save `ctx.s` into `ctx.olds` and return `false` (changed,
  break out of the while loop).

See also: [`concore_read`](@ref).
"""
function unchanged(ctx::ConCoreContext)::Bool
    if ctx.olds == ctx.s
        ctx.s = ""
        return true
    else
        ctx.olds = ctx.s
        return false
    end
end

"""
    unchanged() -> Bool

Sync detection — module-global version.

# Example
```julia
while unchanged()
    ym = concore_read(1, "ym", "[0.0, 0.0]")
end
```
"""
function unchanged()::Bool
    global s, olds
    if olds == s
        s = ""
        return true
    else
        olds = s
        return false
    end
end

# =============================================================================
# concore_init!
# =============================================================================

"""
    concore_init!(ctx::ConCoreContext)

Initialize context by loading port configs, parameters, and maxtime.

Reads `concore.iport`, `concore.oport`, `{inpath}1/concore.params`, and
`{inpath}1/concore.maxtime` from the filesystem.

Called automatically during module initialization for the module-level
globals.  For context-based usage, call explicitly after creating a context.
"""
function concore_init!(ctx::ConCoreContext)
    load_iport!(ctx)
    load_oport!(ctx)
    load_params!(ctx)
    default_maxtime!(ctx, 100)
    return ctx
end

"""
    concore_init!()

Initialize the module-level globals by loading port configs, parameters,
and maxtime from the filesystem.

Called automatically when the module loads.  Can be called again to
re-read configuration files after they change.
"""
function concore_init!()
    load_iport!()
    load_oport!()
    load_params!()
    default_maxtime!(100)
    return nothing
end
