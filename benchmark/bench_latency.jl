# bench_latency.jl -- Latency distribution and tail latency benchmarks
#
# For neuromodulation closed-loop control, TAIL LATENCY matters more than
# average latency.  A GC pause or scheduling hiccup at the wrong moment
# can cause a missed control deadline.  This benchmark suite measures:
#
#   - Percentile analysis: p50, p95, p99, p99.9
#   - Jitter measurement (stddev of latencies)
#   - GC impact on tail latency
#   - Latency distributions for all hot-path operations
#
# Julia's advantage: predictable latency with minimal GC pressure due to
# stack allocation and type stability.  Python's interpreter adds ~10-50μs
# of unpredictable overhead per operation.

# Load Concore from the project root
if !isdefined(Main, :Concore)
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using Concore
end

# ─── Helpers ─────────────────────────────────────────────────────────────────

if !@isdefined(_bench)
"""Run `f()` for `n` iterations, return (min, mean, median) in seconds."""
function _bench(f, n::Int)
    times = Vector{Float64}(undef, n)
    for i in 1:n
        times[i] = @elapsed f()
    end
    sort!(times)
    mn = minimum(times)
    avg = sum(times) / n
    med = times[div(n + 1, 2)]
    return (; min=mn, mean=avg, median=med)
end
end

# ─── Percentile computation ──────────────────────────────────────────────────

"""
Collect `n` latency samples from `f()`, return full distribution analysis.

Returns a NamedTuple with:
  - min, max, mean, median
  - p50, p95, p99, p999 (percentiles)
  - stddev (jitter)
  - samples (sorted raw data for histogram analysis)
"""
function _latency_distribution(f, n::Int)
    # Warmup
    for _ in 1:min(100, n ÷ 10)
        f()
    end

    times = Vector{Float64}(undef, n)
    for i in 1:n
        times[i] = @elapsed f()
    end

    sort!(times)

    mn      = times[1]
    mx      = times[end]
    avg     = sum(times) / n
    med     = times[div(n + 1, 2)]
    p50     = times[max(1, ceil(Int, 0.50 * n))]
    p95     = times[max(1, ceil(Int, 0.95 * n))]
    p99     = times[max(1, ceil(Int, 0.99 * n))]
    p999    = times[max(1, ceil(Int, 0.999 * n))]
    stddev  = sqrt(sum((t - avg)^2 for t in times) / n)

    return (;
        min=mn, max=mx, mean=avg, median=med,
        p50=p50, p95=p95, p99=p99, p999=p999,
        stddev=stddev, samples=times,
    )
end

"""Print a latency distribution in a formatted table."""
function _print_distribution(name::String, d; unit_scale=1e6, unit_name="μs")
    s(v) = round(v * unit_scale; digits=2)
    println("    $(rpad(name, 26)): p50=$(s(d.p50))$(unit_name)  p95=$(s(d.p95))$(unit_name)  " *
            "p99=$(s(d.p99))$(unit_name)  p99.9=$(s(d.p999))$(unit_name)")
    println("    $(rpad("", 26))  min=$(s(d.min))$(unit_name)  max=$(s(d.max))$(unit_name)  " *
            "stddev=$(s(d.stddev))$(unit_name)")
end

# ─── Constants ───────────────────────────────────────────────────────────────

const LAT_N_SAMPLES = 50_000   # Large sample for reliable percentiles

# ─── Test inputs ─────────────────────────────────────────────────────────────

const LAT_SMALL_INPUT  = "[0.0, 1.0]"
const LAT_MEDIUM_INPUT = "[0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]"
const LAT_FORMAT_VEC   = [0.0, 1.0, 2.0, 3.0, 4.0]

# ─── Run benchmarks ─────────────────────────────────────────────────────────

function run_latency_benchmarks()
    results = Dict{String, Any}()

    println("Latency Distribution Benchmarks ($(LAT_N_SAMPLES) samples each)")
    println("=" ^ 70)

    # ── Parse latency distribution ────────────────────────────────────
    println()
    println("  Parse Latency Distribution")
    println("  " * "-" ^ 50)

    d = _latency_distribution(() -> Concore.safe_parse_list(LAT_SMALL_INPUT), LAT_N_SAMPLES)
    results["parse_small_latency"] = d
    _print_distribution("parse small (2 elem)", d)

    d = _latency_distribution(() -> Concore.safe_parse_list(LAT_MEDIUM_INPUT), LAT_N_SAMPLES)
    results["parse_medium_latency"] = d
    _print_distribution("parse medium (10 elem)", d)

    # ── Format latency distribution ───────────────────────────────────
    println()
    println("  Format Latency Distribution")
    println("  " * "-" ^ 50)

    d = _latency_distribution(() -> Concore._format_wire(LAT_FORMAT_VEC), LAT_N_SAMPLES)
    results["format_latency"] = d
    _print_distribution("format (5 elem)", d)

    # ── File I/O latency distribution ────────────────────────────────
    println()
    println("  File I/O Latency Distribution")
    println("  " * "-" ^ 50)

    dir = mktempdir()
    outd = joinpath(dir, "out1")
    ind  = joinpath(dir, "in1")
    mkpath(outd)
    mkpath(ind)

    # Write latency
    write_path = joinpath(outd, "signal")
    wire = Concore._format_wire([0.0, 1.0, 2.0, 3.0, 4.0])
    function _lat_write()
        open(write_path, "w") do f
            write(f, wire)
        end
    end
    _lat_write()  # warmup
    d = _latency_distribution(_lat_write, LAT_N_SAMPLES)
    results["file_write_latency"] = d
    _print_distribution("file write", d)

    # Read+parse latency
    read_path = joinpath(ind, "signal")
    open(read_path, "w") do f
        write(f, wire)
    end
    function _lat_read()
        raw = read(read_path, String)
        Concore.safe_parse_list(raw)
    end
    _lat_read()  # warmup
    d = _latency_distribution(_lat_read, LAT_N_SAMPLES)
    results["file_read_latency"] = d
    _print_distribution("file read+parse", d)

    # Full write+copy+read cycle latency
    function _lat_cycle()
        open(write_path, "w") do f
            write(f, wire)
        end
        cp(write_path, read_path; force=true)
        raw = read(read_path, String)
        Concore.safe_parse_list(raw)
    end
    _lat_cycle()  # warmup
    d = _latency_distribution(_lat_cycle, LAT_N_SAMPLES)
    results["full_cycle_latency"] = d
    _print_distribution("full write+read cycle", d)

    # ── GC impact measurement ────────────────────────────────────────
    println()
    println("  GC Impact Analysis")
    println("  " * "-" ^ 50)

    # Measure parse latency with forced GC every N iterations
    gc_samples = 10_000
    times_no_gc = Vector{Float64}(undef, gc_samples)
    times_with_gc = Vector{Float64}(undef, gc_samples)

    # Without GC interference
    for i in 1:gc_samples
        times_no_gc[i] = @elapsed Concore.safe_parse_list(LAT_MEDIUM_INPUT)
    end

    # With GC forced every 100 iterations (simulates GC pressure)
    for i in 1:gc_samples
        if i % 100 == 0
            GC.gc(false)  # minor GC
        end
        times_with_gc[i] = @elapsed Concore.safe_parse_list(LAT_MEDIUM_INPUT)
    end

    sort!(times_no_gc)
    sort!(times_with_gc)

    p99_no_gc   = times_no_gc[max(1, ceil(Int, 0.99 * gc_samples))]
    p999_no_gc  = times_no_gc[max(1, ceil(Int, 0.999 * gc_samples))]
    p99_with_gc  = times_with_gc[max(1, ceil(Int, 0.99 * gc_samples))]
    p999_with_gc = times_with_gc[max(1, ceil(Int, 0.999 * gc_samples))]

    results["gc_p99_no_gc"]    = p99_no_gc
    results["gc_p999_no_gc"]   = p999_no_gc
    results["gc_p99_with_gc"]  = p99_with_gc
    results["gc_p999_with_gc"] = p999_with_gc

    println("    Parse (no GC pressure)  : p99=$(round(p99_no_gc * 1e6; digits=2))μs  " *
            "p99.9=$(round(p999_no_gc * 1e6; digits=2))μs")
    println("    Parse (with minor GC)   : p99=$(round(p99_with_gc * 1e6; digits=2))μs  " *
            "p99.9=$(round(p999_with_gc * 1e6; digits=2))μs")

    gc_impact = p999_with_gc > 0 && p999_no_gc > 0 ?
        round(p999_with_gc / p999_no_gc; digits=2) : NaN
    results["gc_impact_ratio"] = gc_impact
    println("    GC tail impact (p99.9)  : $(gc_impact)x")
    println("    NOTE: Julia's GC is generational — minor collections are fast.")
    println("          Python's GC (reference counting + cyclic) has higher overhead.")

    # ── Jitter analysis ──────────────────────────────────────────────
    println()
    println("  Jitter Summary (stddev of latencies)")
    println("  " * "-" ^ 50)

    for (key, label) in [
        ("parse_small_latency", "Parse small"),
        ("parse_medium_latency", "Parse medium"),
        ("format_latency", "Format"),
        ("file_write_latency", "File write"),
        ("file_read_latency", "File read+parse"),
        ("full_cycle_latency", "Full cycle"),
    ]
        if haskey(results, key)
            d = results[key]
            jitter = d.stddev
            println("    $(rpad(label, 22)) : stddev=$(round(jitter * 1e6; digits=2))μs  " *
                    "($(round(jitter / d.mean * 100; digits=1))% of mean)")
        end
    end

    # ── Latency histogram (text-based) ───────────────────────────────
    println()
    println("  Latency Histogram: Parse medium (10 elem)")
    println("  " * "-" ^ 50)

    d = results["parse_medium_latency"]
    _print_histogram(d.samples)

    println()

    # Cleanup
    rm(dir; recursive=true, force=true)

    return results
end

"""Print a simple text-based histogram of latency samples."""
function _print_histogram(samples::Vector{Float64}; n_buckets=10, max_bar=40)
    mn = samples[1]
    mx = samples[end]
    if mx ≈ mn
        println("    All samples identical: $(round(mn * 1e6; digits=2))μs")
        return
    end

    bucket_width = (mx - mn) / n_buckets
    counts = zeros(Int, n_buckets)

    for s in samples
        idx = min(n_buckets, max(1, ceil(Int, (s - mn) / bucket_width)))
        counts[idx] += 1
    end

    max_count = maximum(counts)
    scale = max_count > max_bar ? max_count / max_bar : 1.0

    for i in 1:n_buckets
        lo = mn + (i - 1) * bucket_width
        hi = mn + i * bucket_width
        bar_len = max(0, round(Int, counts[i] / scale))
        bar = "█" ^ bar_len
        pct = round(counts[i] / length(samples) * 100; digits=1)
        println("    $(lpad(round(lo * 1e6; digits=1), 8))μs - $(lpad(round(hi * 1e6; digits=1), 8))μs | $(rpad(bar, max_bar)) $(pct)%")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_latency_benchmarks()
end
