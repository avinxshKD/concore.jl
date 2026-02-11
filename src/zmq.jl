# zmq.jl -- ZeroMQ backend for network-distributed communication
#
# The Python concore implementation supports ZeroMQ for distributing a study
# across networked machines.  This module provides the Julia equivalent.
#
# ZMQ.jl is an **optional** dependency.  If it is not installed, the backend
# type is still defined (so code can reference `ZeroMQBackend` in type
# annotations) but all socket operations will error with a helpful message.

# =============================================================================
# Soft dependency on ZMQ.jl
# =============================================================================

"""
    HAS_ZMQ::Bool

`true` if the `ZMQ` package is installed and loaded, `false` otherwise.

All ZeroMQ socket operations check this flag and throw an informative
`ErrorException` when ZMQ is unavailable.
"""
const HAS_ZMQ = try
    @eval using ZMQ
    true
catch
    false
end

function _require_zmq()
    HAS_ZMQ && return
    error(
        "ZMQ.jl is not installed. Install it with:\n" *
        "  using Pkg; Pkg.add(\"ZMQ\")\n" *
        "then restart Julia."
    )
end

# =============================================================================
# Backend type
# =============================================================================

"""
    ZeroMQBackend <: AbstractBackend

Network-distributed communication via ZeroMQ sockets.

Unlike [`FileBackend`](@ref) and [`SharedMemoryBackend`](@ref), the ZeroMQ
backend does not use filesystem paths.  Instead, named ports are registered
with [`init_zmq_port`](@ref) and data flows over TCP (or inproc) sockets.

Requires the `ZMQ` package to be installed (`Pkg.add("ZMQ")`).

# Example
```julia
ctx = ConCoreContext(backend = ZeroMQBackend())
init_zmq_port("plant_out", :output, "tcp://*:5555", :PUB)
init_zmq_port("ctrl_in",   :input,  "tcp://localhost:5555", :SUB)
```

See also: [`init_zmq_port`](@ref), [`zmq_read`](@ref), [`zmq_write`](@ref).
"""
struct ZeroMQBackend <: AbstractBackend end

# Path helpers — ZeroMQ does not use filesystem paths, but the abstract
# interface requires these.  They return a sentinel prefix; actual I/O
# bypasses the path entirely and goes through the socket registry.
_backend_inpath(::ZeroMQBackend)  = "zmq://in"
_backend_outpath(::ZeroMQBackend) = "zmq://out"

# =============================================================================
# ZeroMQPort and registry
# =============================================================================

"""
    ZeroMQPort

Wraps a ZMQ socket together with its metadata.

# Fields
- `context`   — the `ZMQ.Context` that owns the socket.
- `socket`    — the `ZMQ.Socket` used for send/recv.
- `port_type` — `:input` or `:output`.
- `address`   — the ZMQ address string (e.g. `"tcp://*:5555"`).
"""
mutable struct ZeroMQPort
    context::Any   # ZMQ.Context (Any to avoid hard dep at parse time)
    socket::Any    # ZMQ.Socket
    port_type::Symbol
    address::String
end

"""
    _zmq_ports

Global registry of named ZeroMQ ports, keyed by port name.

Analogous to the Python `concore.zmq_ports` dictionary.
"""
const _zmq_ports = Dict{String, ZeroMQPort}()

# =============================================================================
# Port initialisation
# =============================================================================

# Mapping from user-facing Symbol to ZMQ constant.
# Evaluated lazily (at call time) so that ZMQ constants are available.
function _zmq_socket_type(sym::Symbol)
    _require_zmq()
    sym == :REQ  && return @eval ZMQ.REQ
    sym == :REP  && return @eval ZMQ.REP
    sym == :PUB  && return @eval ZMQ.PUB
    sym == :SUB  && return @eval ZMQ.SUB
    sym == :PUSH && return @eval ZMQ.PUSH
    sym == :PULL && return @eval ZMQ.PULL
    error("Unknown ZMQ socket type: $sym. " *
          "Supported types: :REQ, :REP, :PUB, :SUB, :PUSH, :PULL")
end

"""
    init_zmq_port(port_name, port_type, address, socket_type)

Register a named ZeroMQ port.

# Arguments
- `port_name::String`  — unique name for this port (used in `zmq_read`/`zmq_write`).
- `port_type::Symbol`  — `:input` (connects) or `:output` (binds).
- `address::String`    — ZMQ endpoint, e.g. `"tcp://*:5555"` or `"tcp://host:5555"`.
- `socket_type::Symbol`— one of `:REQ`, `:REP`, `:PUB`, `:SUB`, `:PUSH`, `:PULL`.

# Example
```julia
init_zmq_port("plant_out", :output, "tcp://*:5555", :PUB)
init_zmq_port("ctrl_in",   :input,  "tcp://localhost:5555", :SUB)
```

See also: [`zmq_read`](@ref), [`zmq_write`](@ref), [`terminate_zmq`](@ref).
"""
function init_zmq_port(
    port_name::String,
    port_type::Symbol,
    address::String,
    socket_type::Symbol,
)
    _require_zmq()

    if port_type !== :input && port_type !== :output
        error("port_type must be :input or :output, got :$port_type")
    end

    # Close existing port with the same name, if any
    if haskey(_zmq_ports, port_name)
        _close_zmq_port(_zmq_ports[port_name])
        delete!(_zmq_ports, port_name)
    end

    ctx = @eval ZMQ.Context()
    sock_type = _zmq_socket_type(socket_type)
    socket = @eval ZMQ.Socket($ctx, $sock_type)

    # Set timeouts (2 000 ms, matching Python concore)
    @eval ZMQ.set_rcvtimeo($socket, 2000)
    @eval ZMQ.set_sndtimeo($socket, 2000)
    @eval ZMQ.set_linger($socket, 0)

    if port_type == :output
        @eval ZMQ.bind($socket, $address)
    else
        @eval ZMQ.connect($socket, $address)
    end

    _zmq_ports[port_name] = ZeroMQPort(ctx, socket, port_type, address)
    @debug "init_zmq_port" port_name port_type address socket_type
    return nothing
end

# =============================================================================
# zmq_read
# =============================================================================

"""
    zmq_read(port_name, name, initstr; max_retries=5) -> Vector{Float64}

Read data from a registered ZeroMQ port with retry logic.

The function receives a wire-format message (`[simtime, v1, v2, ...]`),
updates the module-global `simtime`, and returns the data portion.

Falls back to parsing `initstr` if all retries are exhausted.

# Arguments
- `port_name::String`     — name passed to [`init_zmq_port`](@ref).
- `name::String`          — signal name (for logging; not used in addressing).
- `initstr::String`       — fallback wire-format string.
- `max_retries::Int=5`    — number of receive attempts before falling back.

# Returns
`Vector{Float64}` — data values (without simtime), same as `concore_read`.

See also: [`zmq_write`](@ref), [`init_zmq_port`](@ref).
"""
function zmq_read(
    port_name::String,
    name::String,
    initstr::String;
    max_retries::Int = 5,
)::Vector{Float64}
    _require_zmq()

    if !haskey(_zmq_ports, port_name)
        error("ZMQ port '$port_name' not registered. Call init_zmq_port first.")
    end

    global simtime
    port = _zmq_ports[port_name]

    for attempt in 1:max_retries
        try
            msg = String(@eval ZMQ.recv($(port.socket)))
            if !isempty(msg)
                parsed = safe_parse_list(msg)
                if length(parsed) >= 1
                    simtime = max(simtime, parsed[1])
                    return parsed[2:end]
                end
            end
        catch e
            @debug "zmq_read: attempt $attempt failed" port_name name exception=(e, catch_backtrace())
            if attempt < max_retries
                sleep(0.5)
                continue
            end
        end
    end

    # Fallback to initstr
    @debug "zmq_read: all retries exhausted, using initstr" port_name name
    return initval(initstr)
end

# =============================================================================
# zmq_write
# =============================================================================

"""
    zmq_write(port_name, name, val; delta=0)

Write data to a registered ZeroMQ port with retry logic.

Sends the wire-format string `[simtime + delta, val...]` over the socket.

# Arguments
- `port_name::String`     — name passed to [`init_zmq_port`](@ref).
- `name::String`          — signal name (for logging).
- `val::Vector{Float64}`  — data values to send.
- `delta::Int=0`          — time increment added to simtime in the output.

See also: [`zmq_read`](@ref), [`init_zmq_port`](@ref).
"""
function zmq_write(
    port_name::String,
    name::String,
    val::Vector{Float64};
    delta::Int = 0,
)
    _require_zmq()

    if !haskey(_zmq_ports, port_name)
        error("ZMQ port '$port_name' not registered. Call init_zmq_port first.")
    end

    global simtime
    port = _zmq_ports[port_name]
    wire = _format_wire(vcat(simtime + delta, val))

    for attempt in 1:5
        try
            @eval ZMQ.send($(port.socket), $wire)
            simtime += delta
            @debug "zmq_write" port_name name wire simtime
            return nothing
        catch e
            @debug "zmq_write: attempt $attempt failed" port_name name exception=(e, catch_backtrace())
            if attempt < 5
                sleep(0.5)
                continue
            end
            rethrow(e)
        end
    end
end

# =============================================================================
# Cleanup
# =============================================================================

"""
    _close_zmq_port(port::ZeroMQPort)

Close a single ZeroMQ port's socket and context.  Errors are suppressed.
"""
function _close_zmq_port(port::ZeroMQPort)
    try
        @eval ZMQ.close($(port.socket))
    catch e
        @debug "_close_zmq_port: socket close failed" exception=(e, catch_backtrace())
    end
    try
        @eval ZMQ.close($(port.context))
    catch e
        @debug "_close_zmq_port: context close failed" exception=(e, catch_backtrace())
    end
end

"""
    terminate_zmq()

Close all registered ZeroMQ sockets and contexts, then clear the registry.

Call this when shutting down or between test runs to release resources.

# Example
```julia
terminate_zmq()
@assert isempty(Concore._zmq_ports)
```

See also: [`init_zmq_port`](@ref).
"""
function terminate_zmq()
    for (name, port) in _zmq_ports
        _close_zmq_port(port)
        @debug "terminate_zmq: closed port" name
    end
    empty!(_zmq_ports)
    @debug "terminate_zmq: all ports released"
    return nothing
end
