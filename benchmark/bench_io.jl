# bench_io.jl -- Benchmarks for concore file I/O (write + read cycles)
#
# Measures raw file write/read throughput using the concore wire protocol.
# Uses a temp directory to avoid polluting the workspace.

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

# ─── Benchmark functions ─────────────────────────────────────────────────────

function setup_bench_dir()
    dir = mktempdir()
    indir = joinpath(dir, "in1")
    outdir = joinpath(dir, "out1")
    mkpath(indir)
    mkpath(outdir)
    return dir, indir, outdir
end

"""Single write + read cycle using raw file ops and parser (no sleep/retry)."""
function bench_single_write_read(outdir::String, indir::String)
    val = [0.0, 42.0, 3.14]
    wire = Concore._format_wire(val)
    filepath = joinpath(outdir, "signal")

    # Write
    open(filepath, "w") do f
        write(f, wire)
    end

    # "Connect" output to input (symlink or copy)
    inpath = joinpath(indir, "signal")
    cp(filepath, inpath; force=true)

    # Read + parse
    raw = read(inpath, String)
    parsed = Concore.safe_parse_list(raw)
    return parsed
end

"""Write throughput: how many writes per second."""
function bench_write_throughput(outdir::String, n::Int)
    val = [0.0, 1.0, 2.0, 3.0, 4.0]
    wire = Concore._format_wire(val)
    filepath = joinpath(outdir, "signal")

    t = @elapsed begin
        for _ in 1:n
            open(filepath, "w") do f
                write(f, wire)
            end
        end
    end
    return t
end

"""Read throughput: how many read+parse per second."""
function bench_read_throughput(indir::String, n::Int)
    # Pre-write a file to read
    filepath = joinpath(indir, "signal")
    wire = Concore._format_wire([0.0, 1.0, 2.0, 3.0, 4.0])
    open(filepath, "w") do f
        write(f, wire)
    end

    t = @elapsed begin
        for _ in 1:n
            raw = read(filepath, String)
            Concore.safe_parse_list(raw)
        end
    end
    return t
end

# ─── Run benchmarks ─────────────────────────────────────────────────────────

const N_SINGLE = 1_000
const N_CYCLE  = 100
const N_THROUGHPUT = 10_000

function run_io_benchmarks()
    results = Dict{String, Any}()

    dir, ind, outd = setup_bench_dir()

    # Warmup
    bench_single_write_read(outd, ind)

    println("File I/O Benchmarks")
    println("=" ^ 70)

    # Single write+read
    r = _bench(() -> bench_single_write_read(outd, ind), N_SINGLE)
    results["single_write_read"] = r
    println("  single write+read       : min=$(round(r.min * 1e6; digits=2))μs  " *
            "median=$(round(r.median * 1e6; digits=2))μs")

    # 100-cycle control loop simulation (no sleep)
    n_cycle_repeats = 50
    cycle_time = _bench(n_cycle_repeats) do
        for _ in 1:N_CYCLE  # N_CYCLE = 100 iterations per timing
            bench_single_write_read(outd, ind)
        end
    end
    results["100_cycle"] = cycle_time
    per_iter = cycle_time.median / N_CYCLE
    println("  100-cycle loop          : median=$(round(cycle_time.median * 1e3; digits=2))ms  " *
            "($(round(per_iter * 1e6; digits=2))μs/iter)")

    # Write throughput
    wt = bench_write_throughput(outd, N_THROUGHPUT)
    wps = N_THROUGHPUT / wt
    results["write_throughput_ops_sec"] = wps
    println("  write throughput        : $(round(Int, wps)) writes/sec  " *
            "($(N_THROUGHPUT) ops in $(round(wt * 1e3; digits=1))ms)")

    # Read throughput
    rt = bench_read_throughput(ind, N_THROUGHPUT)
    rps = N_THROUGHPUT / rt
    results["read_throughput_ops_sec"] = rps
    println("  read+parse throughput   : $(round(Int, rps)) reads/sec  " *
            "($(N_THROUGHPUT) ops in $(round(rt * 1e3; digits=1))ms)")

    println()

    # Cleanup
    rm(dir; recursive=true, force=true)

    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_io_benchmarks()
end
