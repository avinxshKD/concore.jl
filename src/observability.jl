# observability.jl -- Real-time metrics and observability for concore simulations
#
# Provides a zero-cost-when-disabled metrics collection system for profiling
# and debugging closed-loop control simulations.  Tracks read/write latencies,
# throughput, sync wait times, error rates, and per-iteration timings.
#
# Thread-safe via ReentrantLock.  All public functions come in two flavours:
#   1. Explicit collector:  func(collector, ...)
#   2. Module-global:       func(...)  — operates on `_global_collector`
#
# Design principles:
#   - Zero overhead when disabled (single Bool check, no allocations)
#   - Non-intrusive (does not modify protocol.jl)
#   - Works with both module-global and context-based APIs
#   - No external dependencies (stdlib Printf only)

using Printf: @sprintf

# =============================================================================
# Lightweight statistics (avoid Statistics.jl dependency)
# =============================================================================

"""Arithmetic mean of a non-empty vector."""
_obs_mean(v::Vector{Float64}) = sum(v) / length(v)

"""Median of a non-empty sorted vector."""
function _obs_median(sorted::Vector{Float64})
    n = length(sorted)
    if isodd(n)
        return sorted[(n + 1) ÷ 2]
    else
        return (sorted[n ÷ 2] + sorted[n ÷ 2 + 1]) / 2.0
    end
end

"""
    _obs_quantile(sorted::Vector{Float64}, p::Float64) -> Float64

Compute the `p`-th quantile (0 ≤ p ≤ 1) of a pre-sorted vector using
linear interpolation (matches Julia's default `:linear` method).
"""
function _obs_quantile(sorted::Vector{Float64}, p::Float64)
    n = length(sorted)
    n == 1 && return sorted[1]
    # Virtual index (1-based)
    h = 1.0 + p * (n - 1)
    lo = floor(Int, h)
    hi = ceil(Int, h)
    lo = clamp(lo, 1, n)
    hi = clamp(hi, 1, n)
    lo == hi && return sorted[lo]
    frac = h - lo
    return sorted[lo] * (1.0 - frac) + sorted[hi] * frac
end

# =============================================================================
# Module-level enable flag
# =============================================================================

"""Module-level flag controlling whether metrics are collected."""
global _metrics_enabled::Bool = false

"""Module-level global metrics collector (lazily used)."""
global _global_collector::Union{Nothing,Any} = nothing  # typed after struct def

# =============================================================================
# MetricsCollector
# =============================================================================

"""
    MetricsCollector

Collects performance metrics for concore read/write operations.

Tracks operation counts, latencies, data volumes, sync wait times, iteration
durations, and error counts.  All fields are protected by a `ReentrantLock`
for thread safety.

Create with [`metrics_collector`](@ref).  Record events with
[`record_read!`](@ref), [`record_write!`](@ref), [`record_sync_wait!`](@ref),
and [`record_iteration!`](@ref).  Summarise with [`get_summary`](@ref).

# Fields
| Field                | Type             | Description                          |
|:-------------------- |:---------------- |:------------------------------------ |
| `read_count`         | `Int`            | Total number of reads recorded       |
| `write_count`        | `Int`            | Total number of writes recorded      |
| `read_latencies`     | `Vector{Float64}`| Per-read latency in seconds          |
| `write_latencies`    | `Vector{Float64}`| Per-write latency in seconds         |
| `sync_wait_times`    | `Vector{Float64}`| Per-sync-loop wait durations (s)     |
| `iteration_times`    | `Vector{Float64}`| Per-control-loop iteration times (s) |
| `total_bytes_read`   | `Int`            | Cumulative bytes read                |
| `total_bytes_written`| `Int`            | Cumulative bytes written             |
| `errors_count`       | `Int`            | Total failed operations              |
| `start_time`         | `Float64`        | `time()` when collector was created  |
| `lock`               | `ReentrantLock`  | Guards all mutable state             |
| `enabled`            | `Bool`           | Per-collector enable flag            |

See also: [`metrics_collector`](@ref), [`get_summary`](@ref),
[`print_metrics`](@ref), [`export_metrics`](@ref).
"""
mutable struct MetricsCollector
    read_count::Int
    write_count::Int
    read_latencies::Vector{Float64}
    write_latencies::Vector{Float64}
    sync_wait_times::Vector{Float64}
    iteration_times::Vector{Float64}
    total_bytes_read::Int
    total_bytes_written::Int
    errors_count::Int
    start_time::Float64
    lock::ReentrantLock
    enabled::Bool
end

function Base.show(io::IO, mc::MetricsCollector)
    print(io, "MetricsCollector(reads=", mc.read_count,
          ", writes=", mc.write_count,
          ", errors=", mc.errors_count,
          ", enabled=", mc.enabled, ")")
end

# =============================================================================
# Constructor / Reset
# =============================================================================

"""
    metrics_collector(; enabled::Bool=true) -> MetricsCollector

Create a new metrics collector.

The collector starts with all counters at zero and `start_time` set to the
current time.  Pass `enabled=false` to create a dormant collector that
silently ignores all `record_*!` calls.

# Example
```julia
mc = metrics_collector()
# ... run simulation, recording metrics ...
summary = get_summary(mc)
```

See also: [`reset_metrics!`](@ref), [`enable_metrics!`](@ref).
"""
function metrics_collector(; enabled::Bool = true)::MetricsCollector
    MetricsCollector(
        0,                    # read_count
        0,                    # write_count
        Float64[],            # read_latencies
        Float64[],            # write_latencies
        Float64[],            # sync_wait_times
        Float64[],            # iteration_times
        0,                    # total_bytes_read
        0,                    # total_bytes_written
        0,                    # errors_count
        time(),               # start_time
        ReentrantLock(),      # lock
        enabled,              # enabled
    )
end

"""
    reset_metrics!(mc::MetricsCollector)

Clear all collected data and reset counters to zero.

The `start_time` is updated to the current time.  The `enabled` flag is
preserved.

# Example
```julia
reset_metrics!(mc)
```
"""
function reset_metrics!(mc::MetricsCollector)
    lock(mc.lock) do
        mc.read_count = 0
        mc.write_count = 0
        empty!(mc.read_latencies)
        empty!(mc.write_latencies)
        empty!(mc.sync_wait_times)
        empty!(mc.iteration_times)
        mc.total_bytes_read = 0
        mc.total_bytes_written = 0
        mc.errors_count = 0
        mc.start_time = time()
    end
    @debug "MetricsCollector reset"
    return nothing
end

# =============================================================================
# Module-level enable / disable
# =============================================================================

"""
    enable_metrics!(; collector::Union{MetricsCollector,Nothing}=nothing)

Enable module-level metrics collection.

If `collector` is provided it becomes the global collector; otherwise a new
one is created automatically.  After this call, the `@timed_read` and
`@timed_write` macros (and any code checking `_metrics_enabled`) will
record into the global collector.

# Example
```julia
enable_metrics!()
# ... run simulation ...
print_metrics()
disable_metrics!()
```

See also: [`disable_metrics!`](@ref), [`metrics_collector`](@ref).
"""
function enable_metrics!(; collector::Union{MetricsCollector,Nothing} = nothing)
    global _metrics_enabled, _global_collector
    if collector !== nothing
        _global_collector = collector
    elseif _global_collector === nothing
        _global_collector = metrics_collector()
    end
    _metrics_enabled = true
    @debug "Metrics collection enabled"
    return nothing
end

"""
    disable_metrics!()

Disable module-level metrics collection.

The global collector is retained (not cleared) so that
[`get_summary`](@ref) can still be called afterwards.

See also: [`enable_metrics!`](@ref).
"""
function disable_metrics!()
    global _metrics_enabled
    _metrics_enabled = false
    @debug "Metrics collection disabled"
    return nothing
end

"""
    get_global_collector() -> Union{MetricsCollector,Nothing}

Return the module-level global metrics collector, or `nothing` if none has
been created yet.
"""
function get_global_collector()::Union{MetricsCollector,Nothing}
    return _global_collector
end

# =============================================================================
# Recording functions
# =============================================================================

"""
    record_read!(mc::MetricsCollector, latency::Float64, bytes::Int)

Record a single read operation.

# Arguments
- `mc` — the collector to update.
- `latency` — wall-clock time for the read, in seconds.
- `bytes` — number of bytes read.

No-op if `mc.enabled` is `false`.
"""
function record_read!(mc::MetricsCollector, latency::Float64, bytes::Int)
    mc.enabled || return nothing
    lock(mc.lock) do
        mc.read_count += 1
        push!(mc.read_latencies, latency)
        mc.total_bytes_read += bytes
    end
    @debug "record_read!" latency bytes total=mc.read_count
    return nothing
end

"""
    record_write!(mc::MetricsCollector, latency::Float64, bytes::Int)

Record a single write operation.

# Arguments
- `mc` — the collector to update.
- `latency` — wall-clock time for the write, in seconds.
- `bytes` — number of bytes written.

No-op if `mc.enabled` is `false`.
"""
function record_write!(mc::MetricsCollector, latency::Float64, bytes::Int)
    mc.enabled || return nothing
    lock(mc.lock) do
        mc.write_count += 1
        push!(mc.write_latencies, latency)
        mc.total_bytes_written += bytes
    end
    @debug "record_write!" latency bytes total=mc.write_count
    return nothing
end

"""
    record_sync_wait!(mc::MetricsCollector, wait_time::Float64)

Record the total wall-clock time spent in a single `unchanged()` polling
loop (from entry to the first `false` return).

No-op if `mc.enabled` is `false`.
"""
function record_sync_wait!(mc::MetricsCollector, wait_time::Float64)
    mc.enabled || return nothing
    lock(mc.lock) do
        push!(mc.sync_wait_times, wait_time)
    end
    @debug "record_sync_wait!" wait_time
    return nothing
end

"""
    record_iteration!(mc::MetricsCollector, iter_time::Float64)

Record the wall-clock duration of one complete control-loop iteration
(sync wait + compute + write).

No-op if `mc.enabled` is `false`.
"""
function record_iteration!(mc::MetricsCollector, iter_time::Float64)
    mc.enabled || return nothing
    lock(mc.lock) do
        push!(mc.iteration_times, iter_time)
    end
    @debug "record_iteration!" iter_time
    return nothing
end

"""
    record_error!(mc::MetricsCollector)

Increment the error counter by one.

No-op if `mc.enabled` is `false`.
"""
function record_error!(mc::MetricsCollector)
    mc.enabled || return nothing
    lock(mc.lock) do
        mc.errors_count += 1
    end
    @debug "record_error!" total=mc.errors_count
    return nothing
end

# =============================================================================
# Module-global recording convenience wrappers
# =============================================================================

"""
    record_read!(latency::Float64, bytes::Int)

Record a read into the global collector.  No-op if metrics are disabled.
"""
function record_read!(latency::Float64, bytes::Int)
    _metrics_enabled || return nothing
    record_read!(_global_collector::MetricsCollector, latency, bytes)
end

"""
    record_write!(latency::Float64, bytes::Int)

Record a write into the global collector.  No-op if metrics are disabled.
"""
function record_write!(latency::Float64, bytes::Int)
    _metrics_enabled || return nothing
    record_write!(_global_collector::MetricsCollector, latency, bytes)
end

"""
    record_sync_wait!(wait_time::Float64)

Record a sync wait into the global collector.  No-op if metrics are disabled.
"""
function record_sync_wait!(wait_time::Float64)
    _metrics_enabled || return nothing
    record_sync_wait!(_global_collector::MetricsCollector, wait_time)
end

"""
    record_iteration!(iter_time::Float64)

Record an iteration into the global collector.  No-op if metrics are disabled.
"""
function record_iteration!(iter_time::Float64)
    _metrics_enabled || return nothing
    record_iteration!(_global_collector::MetricsCollector, iter_time)
end

"""
    record_error!()

Record an error into the global collector.  No-op if metrics are disabled.
"""
function record_error!()
    _metrics_enabled || return nothing
    record_error!(_global_collector::MetricsCollector)
end

# =============================================================================
# Statistics helpers (internal)
# =============================================================================

"""
    _latency_stats(v::Vector{Float64}) -> NamedTuple

Compute mean, median, p95, p99, min, max for a latency vector.
Returns zeros for all fields if the vector is empty.
"""
function _latency_stats(v::Vector{Float64})
    if isempty(v)
        return (mean = 0.0, median = 0.0, p95 = 0.0, p99 = 0.0,
                min = 0.0, max = 0.0, count = 0)
    end
    sorted = sort(v)
    (
        mean   = _obs_mean(v),
        median = _obs_median(sorted),
        p95    = _obs_quantile(sorted, 0.95),
        p99    = _obs_quantile(sorted, 0.99),
        min    = sorted[1],
        max    = sorted[end],
        count  = length(v),
    )
end

# =============================================================================
# Summary
# =============================================================================

"""
    get_summary(mc::MetricsCollector) -> NamedTuple

Compute a comprehensive summary of all collected metrics.

The returned `NamedTuple` contains:

| Key                    | Type        | Description                                 |
|:---------------------- |:----------- |:------------------------------------------- |
| `read_count`           | `Int`       | Total reads                                 |
| `write_count`          | `Int`       | Total writes                                |
| `errors_count`         | `Int`       | Total errors                                |
| `error_rate`           | `Float64`   | errors / (reads + writes), or 0.0           |
| `total_bytes_read`     | `Int`       | Cumulative bytes read                       |
| `total_bytes_written`  | `Int`       | Cumulative bytes written                    |
| `total_data_transferred`| `Int`      | Sum of bytes read + written                 |
| `uptime`               | `Float64`   | Seconds since collector creation / reset     |
| `read_ops_per_sec`     | `Float64`   | Read throughput                              |
| `write_ops_per_sec`    | `Float64`   | Write throughput                             |
| `read_latency`         | `NamedTuple`| mean/median/p95/p99/min/max/count            |
| `write_latency`        | `NamedTuple`| mean/median/p95/p99/min/max/count            |
| `sync_wait`            | `NamedTuple`| mean/median/p95/p99/min/max/count            |
| `iteration`            | `NamedTuple`| mean/median/p95/p99/min/max/count            |

# Example
```julia
s = get_summary(mc)
println("Mean read latency: ", s.read_latency.mean, " s")
println("Throughput: ", s.read_ops_per_sec, " reads/s")
```

See also: [`print_metrics`](@ref), [`export_metrics`](@ref).
"""
function get_summary(mc::MetricsCollector)
    lock(mc.lock) do
        uptime = time() - mc.start_time
        total_ops = mc.read_count + mc.write_count
        error_rate = total_ops > 0 ? mc.errors_count / total_ops : 0.0
        read_ops_sec = uptime > 0.0 ? mc.read_count / uptime : 0.0
        write_ops_sec = uptime > 0.0 ? mc.write_count / uptime : 0.0

        (
            read_count            = mc.read_count,
            write_count           = mc.write_count,
            errors_count          = mc.errors_count,
            error_rate            = error_rate,
            total_bytes_read      = mc.total_bytes_read,
            total_bytes_written   = mc.total_bytes_written,
            total_data_transferred = mc.total_bytes_read + mc.total_bytes_written,
            uptime                = uptime,
            read_ops_per_sec      = read_ops_sec,
            write_ops_per_sec     = write_ops_sec,
            read_latency          = _latency_stats(copy(mc.read_latencies)),
            write_latency         = _latency_stats(copy(mc.write_latencies)),
            sync_wait             = _latency_stats(copy(mc.sync_wait_times)),
            iteration             = _latency_stats(copy(mc.iteration_times)),
        )
    end
end

"""
    get_summary() -> NamedTuple

Summary of the global collector.  Returns an empty summary if no global
collector exists.
"""
function get_summary()
    gc = _global_collector
    if gc === nothing
        # Return a zero-valued summary
        z = (mean=0.0, median=0.0, p95=0.0, p99=0.0, min=0.0, max=0.0, count=0)
        return (
            read_count=0, write_count=0, errors_count=0, error_rate=0.0,
            total_bytes_read=0, total_bytes_written=0, total_data_transferred=0,
            uptime=0.0, read_ops_per_sec=0.0, write_ops_per_sec=0.0,
            read_latency=z, write_latency=z, sync_wait=z, iteration=z,
        )
    end
    return get_summary(gc::MetricsCollector)
end

# =============================================================================
# Pretty-print
# =============================================================================

"""
    _fmt_time(seconds::Float64) -> String

Human-readable duration string.
"""
function _fmt_time(seconds::Float64)::String
    if seconds < 1e-6
        return @sprintf("%.1f ns", seconds * 1e9)
    elseif seconds < 1e-3
        return @sprintf("%.1f μs", seconds * 1e6)
    elseif seconds < 1.0
        return @sprintf("%.2f ms", seconds * 1e3)
    else
        return @sprintf("%.3f s", seconds)
    end
end

"""
    _fmt_bytes(bytes::Int) -> String

Human-readable byte count.
"""
function _fmt_bytes(bytes::Int)::String
    if bytes < 1024
        return string(bytes, " B")
    elseif bytes < 1024^2
        return @sprintf("%.1f KiB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.1f MiB", bytes / 1024^2)
    else
        return @sprintf("%.1f GiB", bytes / 1024^3)
    end
end

"""
    _print_latency_block(io::IO, label::String, stats::NamedTuple)

Print a formatted latency statistics block.
"""
function _print_latency_block(io::IO, label::String, stats::NamedTuple)
    stats.count == 0 && return
    println(io, "  ", label, " (n=", stats.count, "):")
    println(io, "    mean   = ", _fmt_time(stats.mean))
    println(io, "    median = ", _fmt_time(stats.median))
    println(io, "    p95    = ", _fmt_time(stats.p95))
    println(io, "    p99    = ", _fmt_time(stats.p99))
    println(io, "    min    = ", _fmt_time(stats.min))
    println(io, "    max    = ", _fmt_time(stats.max))
end

"""
    print_metrics(io::IO, mc::MetricsCollector)

Pretty-print a full metrics report to `io`.

Displays operation counts, throughput, latency percentiles, data volumes,
sync wait statistics, iteration statistics, and error rates.

# Example
```julia
print_metrics(stdout, mc)
```

See also: [`get_summary`](@ref), [`export_metrics`](@ref).
"""
function print_metrics(io::IO, mc::MetricsCollector)
    s = get_summary(mc)

    println(io, "╔══════════════════════════════════════════════════════╗")
    println(io, "║            ConCore Metrics Report                   ║")
    println(io, "╠══════════════════════════════════════════════════════╣")
    println(io, "║ Uptime: ", _fmt_time(s.uptime))
    println(io, "║ Status: ", mc.enabled ? "ENABLED" : "DISABLED")
    println(io, "╠══════════════════════════════════════════════════════╣")
    println(io, "║ Operations:")
    println(io, "  Reads:  ", s.read_count,
            "  (", @sprintf("%.1f", s.read_ops_per_sec), " ops/s)")
    println(io, "  Writes: ", s.write_count,
            "  (", @sprintf("%.1f", s.write_ops_per_sec), " ops/s)")
    println(io, "  Errors: ", s.errors_count,
            "  (rate: ", @sprintf("%.4f", s.error_rate), ")")
    println(io, "╠══════════════════════════════════════════════════════╣")
    println(io, "║ Data Transfer:")
    println(io, "  Read:    ", _fmt_bytes(s.total_bytes_read))
    println(io, "  Written: ", _fmt_bytes(s.total_bytes_written))
    println(io, "  Total:   ", _fmt_bytes(s.total_data_transferred))
    println(io, "╠══════════════════════════════════════════════════════╣")
    println(io, "║ Latency Distributions:")
    _print_latency_block(io, "Read Latency", s.read_latency)
    _print_latency_block(io, "Write Latency", s.write_latency)
    _print_latency_block(io, "Sync Wait", s.sync_wait)
    _print_latency_block(io, "Iteration Time", s.iteration)
    println(io, "╚══════════════════════════════════════════════════════╝")
end

"""
    print_metrics(mc::MetricsCollector)

Pretty-print metrics to `stdout`.
"""
print_metrics(mc::MetricsCollector) = print_metrics(stdout, mc)

"""
    print_metrics(io::IO)

Pretty-print the global collector's metrics to `io`.
"""
function print_metrics(io::IO)
    gc = _global_collector
    if gc === nothing
        println(io, "No metrics collector active.  Call enable_metrics!() first.")
        return
    end
    print_metrics(io, gc::MetricsCollector)
end

"""
    print_metrics()

Pretty-print the global collector's metrics to `stdout`.
"""
print_metrics() = print_metrics(stdout)

# =============================================================================
# Export
# =============================================================================

"""
    export_metrics(mc::MetricsCollector, filepath::AbstractString; format::Symbol=:csv)

Export collected metrics to a file.

# Formats
- `:csv` (default) — writes a CSV with columns for each latency sample type.
- `:text` — writes the same pretty-printed report as [`print_metrics`](@ref).

The parent directory is created if it does not exist.

# Example
```julia
export_metrics(mc, "metrics_report.csv")
export_metrics(mc, "metrics_report.txt"; format=:text)
```

See also: [`print_metrics`](@ref), [`get_summary`](@ref).
"""
function export_metrics(
    mc::MetricsCollector,
    filepath::AbstractString;
    format::Symbol = :csv,
)
    mkpath(dirname(abspath(filepath)))

    if format == :text
        open(filepath, "w") do io
            print_metrics(io, mc)
        end
        @debug "export_metrics" filepath format
        return filepath
    end

    # Default: CSV
    # We write one row per sample, with columns:
    #   type, index, value_seconds, bytes
    open(filepath, "w") do io
        println(io, "type,index,value_seconds,bytes")

        lock(mc.lock) do
            for (i, v) in enumerate(mc.read_latencies)
                println(io, "read_latency,", i, ",", v, ",")
            end
            for (i, v) in enumerate(mc.write_latencies)
                println(io, "write_latency,", i, ",", v, ",")
            end
            for (i, v) in enumerate(mc.sync_wait_times)
                println(io, "sync_wait,", i, ",", v, ",")
            end
            for (i, v) in enumerate(mc.iteration_times)
                println(io, "iteration,", i, ",", v, ",")
            end

            # Summary row
            println(io, "# summary")
            println(io, "# read_count=", mc.read_count)
            println(io, "# write_count=", mc.write_count)
            println(io, "# errors_count=", mc.errors_count)
            println(io, "# total_bytes_read=", mc.total_bytes_read)
            println(io, "# total_bytes_written=", mc.total_bytes_written)
        end
    end

    @debug "export_metrics" filepath format
    return filepath
end

"""
    export_metrics(filepath::AbstractString; format::Symbol=:csv)

Export the global collector's metrics.
"""
function export_metrics(filepath::AbstractString; format::Symbol = :csv)
    gc = _global_collector
    gc === nothing && error("No global metrics collector.  Call enable_metrics!() first.")
    return export_metrics(gc::MetricsCollector, filepath; format = format)
end

# =============================================================================
# Timed macros
# =============================================================================

"""
    @timed_read(mc, port, name, initstr)

Wrap a `concore_read` call with automatic latency and byte recording.

Measures wall-clock time around `concore_read(port, name, initstr)` and
records the result into `mc::MetricsCollector`.  Returns the same
`Vector{Float64}` that `concore_read` would.

# Example
```julia
mc = metrics_collector()
ym = @timed_read mc 1 "ym" "[0.0, 0.0]"
```

See also: [`@timed_write`](@ref), [`record_read!`](@ref).
"""
macro timed_read(mc, port, name, initstr)
    quote
        local _mc = $(esc(mc))
        local _t0 = time()
        local _result = concore_read($(esc(port)), $(esc(name)), $(esc(initstr)))
        local _elapsed = time() - _t0
        # Estimate bytes from the wire format length of the init string
        # (actual file bytes are not easily available without modifying protocol.jl)
        local _nbytes = sizeof($(esc(initstr)))
        record_read!(_mc, _elapsed, _nbytes)
        _result
    end
end

"""
    @timed_write(mc, port, name, val)
    @timed_write(mc, port, name, val, delta)

Wrap a `concore_write` call with automatic latency and byte recording.

# Example
```julia
mc = metrics_collector()
@timed_write mc 1 "u" [42.0, 3.14]
```

See also: [`@timed_read`](@ref), [`record_write!`](@ref).
"""
macro timed_write(mc, port, name, val)
    quote
        local _mc = $(esc(mc))
        local _v = $(esc(val))
        local _t0 = time()
        concore_write($(esc(port)), $(esc(name)), _v)
        local _elapsed = time() - _t0
        local _nbytes = _v isa AbstractString ? sizeof(_v) : sizeof(_v) * 8
        record_write!(_mc, _elapsed, _nbytes)
        nothing
    end
end

macro timed_write(mc, port, name, val, delta)
    quote
        local _mc = $(esc(mc))
        local _v = $(esc(val))
        local _t0 = time()
        concore_write($(esc(port)), $(esc(name)), _v; delta = $(esc(delta)))
        local _elapsed = time() - _t0
        local _nbytes = _v isa AbstractString ? sizeof(_v) : sizeof(_v) * 8
        record_write!(_mc, _elapsed, _nbytes)
        nothing
    end
end

# =============================================================================
# Timed sync helper
# =============================================================================

"""
    timed_unchanged(mc::MetricsCollector) -> Bool

Drop-in replacement for `unchanged()` that records sync wait time.

Use in place of `unchanged()` in the polling loop:
```julia
mc = metrics_collector()
while timed_unchanged(mc)
    ym = concore_read(1, "ym", "[0.0, 0.0]")
end
```

When `unchanged()` returns `false` (data changed), the accumulated wait
time since the last `true → false` transition is recorded.

See also: [`record_sync_wait!`](@ref), [`unchanged`](@ref).
"""
function timed_unchanged(mc::MetricsCollector)::Bool
    t0 = time()
    result = unchanged()
    elapsed = time() - t0
    if !result
        # Data changed — record the sync wait for this cycle
        record_sync_wait!(mc, elapsed)
    end
    return result
end

"""
    timed_unchanged(mc::MetricsCollector, ctx::ConCoreContext) -> Bool

Context-based version of [`timed_unchanged`](@ref).
"""
function timed_unchanged(mc::MetricsCollector, ctx::ConCoreContext)::Bool
    t0 = time()
    result = unchanged(ctx)
    elapsed = time() - t0
    if !result
        record_sync_wait!(mc, elapsed)
    end
    return result
end
