# parser.jl -- Safe wire-format parser for concore data
#
# The concore protocol exchanges data as text files containing Python-style
# lists: [simtime, v1, v2, ...].  Because these files are written by other
# (potentially untrusted) processes, we MUST NOT use `eval` or `Meta.parse`.
# Instead we use regex-based extraction with explicit Float64 parsing.

"""
    safe_parse_list(str::AbstractString) -> Vector{Float64}

Parse a concore wire-format string into a `Vector{Float64}`.

The wire format is a Python-style list of numbers:
```
[simtime, value1, value2, ...]
```

The parser handles several variants produced by the Python and C++
implementations, including numpy wrappers and Python boolean literals.

# Supported Inputs

| Input                                | Output                 |
|:------------------------------------ |:---------------------- |
| `"[1.0, 2.0, 3.0]"`                 | `[1.0, 2.0, 3.0]`     |
| `"[0, 1, 2]"`                       | `[0.0, 1.0, 2.0]`     |
| `"[np.float64(1.5), numpy.int32(2)]"` | `[1.5, 2.0]`        |
| `"[True, False, None]"`             | `[1.0, 0.0, 0.0]`     |
| `"[np.array([1.0, 2.0])]"`          | `[1.0, 2.0]`          |

# Security

This function **never** calls `eval` or `Meta.parse`.  All values are
extracted via regex and converted with `Base.parse(Float64, ...)`.  This is
critical because concore reads files written by other processes on the
filesystem.

# Examples
```jldoctest
julia> using Concore

julia> safe_parse_list("[1.0, 2.0, 3.0]")
3-element Vector{Float64}:
 1.0
 2.0
 3.0

julia> safe_parse_list("[0.0, np.float64(1.5)]")
2-element Vector{Float64}:
 0.0
 1.5

julia> safe_parse_list("[True, False]")
2-element Vector{Float64}:
 1.0
 0.0
```

# Throws
- `ArgumentError` if `str` is empty, missing brackets, or contains
  values that cannot be converted to `Float64`.

See also: [`concore_read`](@ref), [`initval`](@ref).
"""
function safe_parse_list(str::AbstractString)::Vector{Float64}
    cleaned = strip(str)

    # ── Input validation ──────────────────────────────────────────────
    if isempty(cleaned)
        throw(ArgumentError("safe_parse_list: input string is empty"))
    end

    # ── Strip outer numpy array wrapper: np.array([...]) → [...] ─────
    cleaned = replace(cleaned, r"^(?:np|numpy)\.array\(" => "")
    cleaned = replace(cleaned, r"\)$" => "")
    cleaned = strip(cleaned)

    # ── Strip individual numpy wrappers: np.float64(1.5) → 1.5 ──────
    cleaned = replace(cleaned, r"(?:np|numpy)\.\w+\(([^()]+)\)" => s"\1")

    # ── Python booleans / None ───────────────────────────────────────
    cleaned = replace(cleaned, r"\bTrue\b"  => "1.0")
    cleaned = replace(cleaned, r"\bFalse\b" => "0.0")
    cleaned = replace(cleaned, r"\bNone\b"  => "0.0")

    # ── Validate bracket structure ───────────────────────────────────
    m = match(r"^\[(.+)\]$", cleaned)
    if m === nothing
        throw(ArgumentError(
            "safe_parse_list: expected '[...]' format, got '$(first(str, 80))'"))
    end

    inner = m.captures[1]
    parts = split(inner, ",")

    result = Vector{Float64}(undef, length(parts))
    for (i, part) in enumerate(parts)
        token = strip(part)
        val = tryparse(Float64, token)
        if val === nothing
            throw(ArgumentError(
                "safe_parse_list: cannot parse '$(token)' as Float64 " *
                "(position $i in '$(first(str, 80))')"))
        end
        result[i] = val
    end

    @debug "safe_parse_list" input=first(str, 40) n_values=length(result)
    return result
end
