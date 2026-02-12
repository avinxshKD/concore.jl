# ConcoreUtils.jl -- Optional utilities for building concore study nodes
#
# Provides:
#   • PIDController / PIDState  — PID control with anti-windup
#   • load_graph                — GraphML workflow parsing
#   • PIDNode                   — backward-compatible alias

"""
    ConcoreUtils

Optional utilities for building concore study nodes.

Provides a PID controller implementation (with anti-windup) and GraphML
workflow parsing for extracting controller parameters from study graph files.

# Usage
```julia
using Concore
using Concore.ConcoreUtils

ctrl  = PIDController("pid1", 2.0, 0.5, 0.1)
state = PIDState()

error_val = setpoint - measurement
u = execute_step(ctrl, state, error_val, dt)
```

The legacy `PIDNode` alias is retained for backward compatibility:
```julia
node = PIDNode("pid1", 2.0, 0.5, 0.1)  # same as PIDController
```
"""
module ConcoreUtils

using EzXML

export PIDController, PIDState, PIDNode
export load_graph, execute_step, reset!

# =============================================================================
# PID Controller — Parameters (immutable)
# =============================================================================

"""
    PIDController

Immutable PID controller parameters.

Separating parameters from state (see [`PIDState`](@ref)) allows clean
resets and makes it clear which values are tuning knobs vs. runtime state.

# Fields
- `id::String`          — node identifier (for logging / graph matching)
- `kp::Float64`         — proportional gain
- `ki::Float64`         — integral gain
- `kd::Float64`         — derivative gain
- `output_min::Float64` — minimum output clamp (anti-windup, default `-Inf`)
- `output_max::Float64` — maximum output clamp (anti-windup, default `+Inf`)

# Constructors
```julia
PIDController(id, kp, ki, kd)                         # no output limits
PIDController(id, kp, ki, kd, output_min, output_max) # with limits
```

# Example
```jldoctest
julia> using Concore.ConcoreUtils

julia> ctrl = PIDController("heater", 2.0, 0.1, 0.05, -10.0, 10.0);

julia> ctrl.kp
2.0
```
"""
struct PIDController
    id::String
    kp::Float64
    ki::Float64
    kd::Float64
    output_min::Float64
    output_max::Float64
end

PIDController(id::AbstractString, kp::Real, ki::Real, kd::Real) =
    PIDController(String(id), Float64(kp), Float64(ki), Float64(kd), -Inf, Inf)

function Base.show(io::IO, c::PIDController)
    print(io, "PIDController(\"", c.id, "\", kp=", c.kp,
          ", ki=", c.ki, ", kd=", c.kd)
    if isfinite(c.output_min) || isfinite(c.output_max)
        print(io, ", limits=[", c.output_min, ", ", c.output_max, "]")
    end
    print(io, ")")
end

# =============================================================================
# PID Controller — State (mutable)
# =============================================================================

"""
    PIDState

Mutable PID controller runtime state.

Separated from [`PIDController`](@ref) parameters so that a controller can
be reset without reconstructing its tuning parameters.

# Fields
- `integral::Float64`   — accumulated integral term
- `prev_error::Float64` — previous error for derivative calculation

# Example
```jldoctest
julia> using Concore.ConcoreUtils

julia> state = PIDState();

julia> state.integral
0.0
```
"""
mutable struct PIDState
    integral::Float64
    prev_error::Float64
end

PIDState() = PIDState(0.0, 0.0)

function Base.show(io::IO, s::PIDState)
    print(io, "PIDState(integral=", round(s.integral; sigdigits=6),
          ", prev_error=", round(s.prev_error; sigdigits=6), ")")
end

# =============================================================================
# PID Step Execution
# =============================================================================

"""
    execute_step(ctrl::PIDController, state::PIDState, error::Float64, dt::Float64=1.0) -> Float64

Execute one PID control iteration and return the (clamped) control output.

Implements the textbook PID law with **anti-windup**:
1. Compute P, I, D terms.
2. Clamp the total output to `[ctrl.output_min, ctrl.output_max]`.
3. If the output is saturated, freeze the integral accumulator (do not
   integrate further in the saturated direction) to prevent windup.

# Arguments
- `ctrl::PIDController` — immutable controller parameters.
- `state::PIDState`     — mutable state (modified in-place).
- `error::Float64`      — current error signal (setpoint − measurement).
- `dt::Float64=1.0`     — time step.

# Returns
`Float64` — the clamped control output.

# Example
```jldoctest
julia> using Concore.ConcoreUtils

julia> ctrl  = PIDController("test", 2.0, 0.5, 0.1);

julia> state = PIDState();

julia> u = execute_step(ctrl, state, 10.0, 1.0);

julia> u == 2.0 * 10.0 + 0.5 * 10.0 + 0.1 * 10.0
true
```
"""
function execute_step(
    ctrl::PIDController,
    state::PIDState,
    error::Float64,
    dt::Float64 = 1.0,
)::Float64
    # Proportional
    p_term = ctrl.kp * error

    # Integral (tentative)
    tentative_integral = state.integral + error * dt
    i_term = ctrl.ki * tentative_integral

    # Derivative
    d_term = ctrl.kd * (error - state.prev_error) / dt

    # Raw output
    output = p_term + i_term + d_term

    # Anti-windup clamping
    clamped = clamp(output, ctrl.output_min, ctrl.output_max)

    if clamped == output
        # Not saturated — accept the integral update
        state.integral = tentative_integral
    else
        # Saturated — freeze integral at its current value to prevent windup.
        # The output is already clamped, so we don't accumulate error that
        # would make the integral term even larger.
    end

    state.prev_error = error
    return clamped
end

# Backward-compatible overload: accept PIDController with embedded state pattern
# (for code that passes PIDNode which is now an alias for PIDController)
"""
    execute_step(ctrl::PIDController, error::Float64, dt::Float64=1.0) -> Float64

Convenience overload that creates a temporary `PIDState`.

!!! warning
    This allocates a new `PIDState` each call and discards it, so integral
    and derivative history is lost.  Prefer the `(ctrl, state, error, dt)`
    form for real control loops.
"""
function execute_step(ctrl::PIDController, error::Float64, dt::Float64 = 1.0)::Float64
    # For backward compat with code using PIDNode, we need a persistent state.
    # Since PIDController is immutable, we use a module-level cache.
    state = get!(_state_cache, ctrl.id, PIDState())
    return execute_step(ctrl, state, error, dt)
end

# Module-level state cache for the convenience overload
const _state_cache = Dict{String, PIDState}()

"""
    reset!(state::PIDState) -> PIDState

Reset PID state to zero (integral and previous error).

# Example
```jldoctest
julia> using Concore.ConcoreUtils

julia> state = PIDState();

julia> state.integral = 42.0;

julia> reset!(state);

julia> state.integral
0.0
```
"""
function reset!(state::PIDState)
    state.integral = 0.0
    state.prev_error = 0.0
    return state
end

"""
    reset!(ctrl_id::AbstractString)

Reset the cached `PIDState` for the controller with the given ID.

Only affects the state cache used by the 2-argument `execute_step` overload.
"""
function reset!(ctrl_id::AbstractString)
    if haskey(_state_cache, ctrl_id)
        reset!(_state_cache[ctrl_id])
    end
    return nothing
end

# =============================================================================
# GraphML Parsing
# =============================================================================

"""
    load_graph(filepath::AbstractString) -> Vector{Tuple{PIDController, PIDState}}

Parse a GraphML file and extract PID controller nodes with their parameters.

Each `<node>` element in the graph is expected to have `<data>` children with
keys `"kp"`, `"ki"`, and `"kd"`.  Missing gains default to `kp=1.0`,
`ki=0.0`, `kd=0.0`.

Returns a vector of `(PIDController, PIDState)` tuples, one per node.

# Example
```julia
controllers = load_graph("study.graphml")
for (ctrl, state) in controllers
    println(ctrl.id, ": kp=", ctrl.kp)
end
```
"""
function load_graph(filepath::AbstractString)::Vector{Tuple{PIDController, PIDState}}
    doc = readxml(filepath)
    root_elem = doc.root
    result = Tuple{PIDController, PIDState}[]

    for graph_elem in eachelement(root_elem)
        gname = nodename(graph_elem)
        (endswith(gname, "graph") || gname == "graph") || continue

        for node_elem in eachelement(graph_elem)
            nname = nodename(node_elem)
            (endswith(nname, "node") || nname == "node") || continue

            id = node_elem["id"]
            kp = _parse_data(node_elem, "kp", 1.0)
            ki = _parse_data(node_elem, "ki", 0.0)
            kd = _parse_data(node_elem, "kd", 0.0)

            ctrl = PIDController(id, kp, ki, kd)
            push!(result, (ctrl, PIDState()))
        end
    end

    return result
end

"""
    _parse_data(elem, key::AbstractString, default::Float64) -> Float64

Extract a `<data key="...">value</data>` child from an XML element.
Returns `default` if the key is not found or cannot be parsed.
"""
function _parse_data(elem, key::AbstractString, default::Float64)::Float64
    for child in eachelement(elem)
        if nodename(child) == "data" && haskey(child, "key") && child["key"] == key
            val = tryparse(Float64, nodecontent(child))
            return val !== nothing ? val : default
        end
    end
    return default
end

# =============================================================================
# Backward Compatibility
# =============================================================================

"""
    PIDNode

Alias for [`PIDController`](@ref), retained for backward compatibility.

New code should use `PIDController` + `PIDState` for cleaner state management.
"""
const PIDNode = PIDController

end # module ConcoreUtils
