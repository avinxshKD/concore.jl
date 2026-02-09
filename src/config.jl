# config.jl -- Configuration loading for concore nodes
#
# Reads port mappings (concore.iport / concore.oport), runtime parameters
# (concore.params), and the maximum simulation time (concore.maxtime).
#
# Every function comes in two flavours:
#   1. Context-based:  func(ctx::ConCoreContext, ...)
#   2. Module-global:  func(...)  — operates on the module-level globals
#                                    for Python API compatibility.

# =============================================================================
# Port configuration files
# =============================================================================

"""
    parse_port_file(filename::AbstractString) -> Dict{String,Int}

Parse a concore port configuration file.

Port files use Python dict syntax:
```
{'edgename': portnumber, 'edgename2': portnumber2}
```

Returns an empty `Dict` if the file is missing or empty.

# Examples
```jldoctest
julia> using Concore

julia> path = tempname();

julia> write(path, "{'ym': 1, 'u': 2}");

julia> result = Concore.parse_port_file(path);

julia> rm(path);

julia> sort(collect(result))
2-element Vector{Pair{String, Int64}}:
 "u" => 2
 "ym" => 1
```
"""
function parse_port_file(filename::AbstractString)::Dict{String,Int}
    result = Dict{String,Int}()
    isfile(filename) || return result

    content = try
        strip(read(filename, String))
    catch e
        @debug "parse_port_file: cannot read file" filename exception=(e, catch_backtrace())
        return result
    end

    isempty(content) && return result

    # Strip outer braces
    content = replace(content, r"^\{" => "")
    content = replace(content, r"\}$" => "")

    # Match 'key': value pairs (handles both single and double quotes)
    for m in eachmatch(r"['\"]([^'\"]+)['\"]\s*:\s*(-?\d+)", content)
        result[m.captures[1]] = parse(Int, m.captures[2])
    end

    @debug "parse_port_file" filename n_ports=length(result) ports=result
    return result
end

# =============================================================================
# Context-based port/param loading
# =============================================================================

"""
    load_iport!(ctx::ConCoreContext) -> Dict{String,Int}

Load input port configuration from `concore.iport` into `ctx.iport`.

The file `concore.iport` is expected in the current working directory and
contains a Python-dict mapping of edge names to port numbers.

Returns the loaded dictionary (also stored in `ctx.iport`).
"""
function load_iport!(ctx::ConCoreContext)
    ctx.iport = parse_port_file("concore.iport")
    return ctx.iport
end

"""
    load_oport!(ctx::ConCoreContext) -> Dict{String,Int}

Load output port configuration from `concore.oport` into `ctx.oport`.

Returns the loaded dictionary (also stored in `ctx.oport`).
"""
function load_oport!(ctx::ConCoreContext)
    ctx.oport = parse_port_file("concore.oport")
    return ctx.oport
end

"""
    load_params!(ctx::ConCoreContext)

Load runtime parameters from `{inpath}1/concore.params` into `ctx.params`.

The params file supports two formats:

1. **Python dict**: `{'gain': 2.5, 'mode': 'auto'}`
2. **Key=value pairs**: `gain=2.5;mode=auto`

Numeric values are stored as `Float64`; everything else as `String`.
Surrounding double quotes (a Windows artefact) are stripped.

See also: [`tryparam`](@ref).
"""
function load_params!(ctx::ConCoreContext)
    params_path = joinpath(_backend_inpath(ctx.backend) * "1", "concore.params")
    isfile(params_path) || return

    sparams = try
        strip(read(params_path, String))
    catch e
        @debug "load_params!: cannot read file" params_path exception=(e, catch_backtrace())
        return
    end

    isempty(sparams) && return

    # Strip surrounding double quotes (Windows path quoting artefact)
    if length(sparams) >= 2 && sparams[1] == '"' && sparams[end] == '"'
        sparams = sparams[2:end-1]
    end

    ctx.params = Dict{String,Any}()

    if startswith(sparams, "{")
        # Python dict format: {'key': value, ...}
        for m in eachmatch(r"['\"]([^'\"]+)['\"]\s*:\s*([^,}]+)", sparams)
            key = m.captures[1]
            val_str = strip(m.captures[2])
            val = tryparse(Float64, val_str)
            ctx.params[key] = val !== nothing ? val : strip(val_str, ['\'', '"'])
        end
    else
        # key=value;key2=value2 format
        for pair in split(sparams, ";")
            kv = split(strip(pair), "="; limit=2)
            length(kv) == 2 || continue
            key = strip(kv[1])
            val_str = strip(kv[2])
            val = tryparse(Float64, val_str)
            ctx.params[key] = val !== nothing ? val : val_str
        end
    end

    @debug "load_params!" n_params=length(ctx.params) keys=collect(keys(ctx.params))
end

"""
    tryparam(ctx::ConCoreContext, name::AbstractString, default) -> Any

Return parameter `name` from `ctx.params`, or `default` if not found.

# Examples
```julia
gain = tryparam(ctx, "gain", 1.0)
mode = tryparam(ctx, "mode", "manual")
```

See also: [`load_params!`](@ref).
"""
tryparam(ctx::ConCoreContext, name::AbstractString, default) =
    get(ctx.params, name, default)

"""
    default_maxtime!(ctx::ConCoreContext, default::Int) -> Int

Read maximum simulation time from `{inpath}1/concore.maxtime`.

If the file does not exist or cannot be parsed, `default` is used instead.
The result is stored in `ctx.maxtime` and also returned.

# Example
```julia
default_maxtime!(ctx, 200)   # use 200 if file is missing
```
"""
function default_maxtime!(ctx::ConCoreContext, default::Int)
    maxtime_path = joinpath(_backend_inpath(ctx.backend) * "1", "concore.maxtime")
    ctx.maxtime = try
        parse(Int, strip(read(maxtime_path, String)))
    catch e
        @debug "default_maxtime!: using default" default exception=(e, catch_backtrace())
        default
    end
    return ctx.maxtime
end

# =============================================================================
# Module-global wrappers (Python API compatibility)
# =============================================================================
# These operate on the module-level globals defined in Concore.jl.
# They are intentionally separate from the context-based API so that
# `Concore.load_iport!()` and friends work exactly like the Python version.

"""
    load_iport!() -> Dict{String,Int}

Load input port configuration from `concore.iport` into the module-level
`Concore.iport` global.  Convenience wrapper that mirrors the Python API.
"""
function load_iport!()
    global iport
    iport = parse_port_file("concore.iport")
    return iport
end

"""
    load_oport!() -> Dict{String,Int}

Load output port configuration from `concore.oport` into the module-level
`Concore.oport` global.
"""
function load_oport!()
    global oport
    oport = parse_port_file("concore.oport")
    return oport
end

"""
    load_params!()

Load runtime parameters from `{inpath}1/concore.params` into the module-level
`Concore.params` global.
"""
function load_params!()
    global params
    params_path = joinpath(inpath * "1", "concore.params")
    isfile(params_path) || return

    sparams = try
        strip(read(params_path, String))
    catch e
        @debug "load_params!: cannot read file" params_path exception=(e, catch_backtrace())
        return
    end

    isempty(sparams) && return

    # Strip surrounding double quotes (Windows path quoting artefact)
    if length(sparams) >= 2 && sparams[1] == '"' && sparams[end] == '"'
        sparams = sparams[2:end-1]
    end

    params = Dict{String,Any}()

    if startswith(sparams, "{")
        for m in eachmatch(r"['\"]([^'\"]+)['\"]\s*:\s*([^,}]+)", sparams)
            key = m.captures[1]
            val_str = strip(m.captures[2])
            val = tryparse(Float64, val_str)
            params[key] = val !== nothing ? val : strip(val_str, ['\'', '"'])
        end
    else
        for pair in split(sparams, ";")
            kv = split(strip(pair), "="; limit=2)
            length(kv) == 2 || continue
            key = strip(kv[1])
            val_str = strip(kv[2])
            val = tryparse(Float64, val_str)
            params[key] = val !== nothing ? val : val_str
        end
    end
end

"""
    tryparam(name::AbstractString, default) -> Any

Return parameter `name` from the module-level `Concore.params`, or `default`.

# Examples
```julia
gain = tryparam("gain", 1.0)
```
"""
tryparam(name::AbstractString, default) = get(params, name, default)

"""
    default_maxtime!(default::Int) -> Int

Read maximum simulation time from `{inpath}1/concore.maxtime`, or use
`default`.  Stores result in the module-level `Concore.maxtime` global.
"""
function default_maxtime!(default::Int)
    global maxtime
    maxtime_path = joinpath(inpath * "1", "concore.maxtime")
    maxtime = try
        parse(Int, strip(read(maxtime_path, String)))
    catch e
        @debug "default_maxtime!: using default" default exception=(e, catch_backtrace())
        default
    end
    return maxtime
end
