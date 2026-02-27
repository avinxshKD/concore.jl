# bench_parser.jl -- Benchmarks for safe_parse_list and _format_wire
#
# Measures parse throughput for various wire-format inputs and the reverse
# formatting direction.  Zero external dependencies (uses @elapsed).

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

# ─── Test inputs ─────────────────────────────────────────────────────────────

const SMALL_INPUT  = "[0.0, 1.0]"
const MEDIUM_INPUT = "[0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]"
const LARGE_INPUT  = "[0.0, " * join(["$i.0" for i in 1:100], ", ") * "]"
const NUMPY_INPUT  = "[np.float64(0.0), np.float64(1.0)]"

const FORMAT_SMALL  = [0.0, 1.0]
const FORMAT_MEDIUM = collect(0.0:9.0)
const FORMAT_LARGE  = vcat(0.0, collect(1.0:100.0))

const N_ITERS = 10_000

# ─── Run benchmarks ─────────────────────────────────────────────────────────

function run_parser_benchmarks()
    results = Dict{String, NamedTuple{(:min, :mean, :median), Tuple{Float64,Float64,Float64}}}()

    # Warmup (JIT compile)
    Concore.safe_parse_list(SMALL_INPUT)
    Concore.safe_parse_list(MEDIUM_INPUT)
    Concore.safe_parse_list(LARGE_INPUT)
    Concore.safe_parse_list(NUMPY_INPUT)
    Concore._format_wire(FORMAT_SMALL)

    println("Parser Benchmarks ($N_ITERS iterations each)")
    println("=" ^ 70)

    results["parse_small"] = _bench(() -> Concore.safe_parse_list(SMALL_INPUT), N_ITERS)
    println("  parse small  (2 elem)   : min=$(round(results["parse_small"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["parse_small"].median * 1e6; digits=2))μs")

    results["parse_medium"] = _bench(() -> Concore.safe_parse_list(MEDIUM_INPUT), N_ITERS)
    println("  parse medium (10 elem)  : min=$(round(results["parse_medium"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["parse_medium"].median * 1e6; digits=2))μs")

    results["parse_large"] = _bench(() -> Concore.safe_parse_list(LARGE_INPUT), N_ITERS)
    println("  parse large  (101 elem) : min=$(round(results["parse_large"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["parse_large"].median * 1e6; digits=2))μs")

    results["parse_numpy"] = _bench(() -> Concore.safe_parse_list(NUMPY_INPUT), N_ITERS)
    println("  parse numpy wrappers    : min=$(round(results["parse_numpy"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["parse_numpy"].median * 1e6; digits=2))μs")

    results["format_small"] = _bench(() -> Concore._format_wire(FORMAT_SMALL), N_ITERS)
    println("  format small (2 elem)   : min=$(round(results["format_small"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["format_small"].median * 1e6; digits=2))μs")

    results["format_medium"] = _bench(() -> Concore._format_wire(FORMAT_MEDIUM), N_ITERS)
    println("  format medium (10 elem) : min=$(round(results["format_medium"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["format_medium"].median * 1e6; digits=2))μs")

    results["format_large"] = _bench(() -> Concore._format_wire(FORMAT_LARGE), N_ITERS)
    println("  format large (101 elem) : min=$(round(results["format_large"].min * 1e6; digits=2))μs  " *
            "median=$(round(results["format_large"].median * 1e6; digits=2))μs")

    println()
    return results
end

# Allow running standalone
if abspath(PROGRAM_FILE) == @__FILE__
    run_parser_benchmarks()
end
