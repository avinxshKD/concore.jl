# bench_loop.jl -- Full control loop benchmark
#
# Simulates 1000 iterations of a controller + plant model (PM) loop using
# the concore wire protocol (file-based IPC, no sleep delays).
# This represents the realistic hot path for closed-loop neuromodulation.

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

# ─── Simulated control loop ─────────────────────────────────────────────────

"""
Simulate a controller+PM loop for `n_iters` iterations.

Each iteration:
  1. Controller reads ym, computes u = -K * ym, writes u
  2. Plant reads u, computes ym = A * ym + B * u, writes ym

All communication goes through file write → parse (the concore hot path).
No sleep delays — this measures pure compute + I/O throughput.
"""
function simulate_control_loop(n_iters::Int)
    dir = mktempdir()
    ctrl_out = joinpath(dir, "ctrl_out")
    pm_out = joinpath(dir, "pm_out")
    mkpath(ctrl_out)
    mkpath(pm_out)

    # Simple proportional controller: u = -K * ym
    K = 0.5
    # Simple first-order plant: ym_next = A * ym + B * u
    A = 0.9
    B = 0.1

    simtime = 0.0
    ym = [1.0]  # initial plant output (disturbance)

    u_path = joinpath(ctrl_out, "u")
    ym_path = joinpath(pm_out, "ym")

    for i in 1:n_iters
        # --- Controller side ---
        # Write ym for controller to read (plant → controller)
        ym_wire = Concore._format_wire(vcat(simtime, ym))
        open(ym_path, "w") do f
            write(f, ym_wire)
        end

        # Controller reads ym
        raw_ym = read(ym_path, String)
        parsed_ym = Concore.safe_parse_list(raw_ym)
        ym_val = parsed_ym[2:end]

        # Controller computes u
        u_val = [-K * ym_val[1]]

        # Controller writes u
        u_wire = Concore._format_wire(vcat(simtime, u_val))
        open(u_path, "w") do f
            write(f, u_wire)
        end

        # --- Plant side ---
        # Plant reads u
        raw_u = read(u_path, String)
        parsed_u = Concore.safe_parse_list(raw_u)
        u_read = parsed_u[2:end]

        # Plant computes next ym
        ym = [A * ym_val[1] + B * u_read[1]]

        simtime += 1.0
    end

    rm(dir; recursive=true, force=true)
    return ym[1]  # return final value for verification
end

# ─── Run benchmarks ─────────────────────────────────────────────────────────

const N_LOOP_ITERS = 1000
const N_REPEATS = 10

function run_loop_benchmarks()
    results = Dict{String, Any}()

    # Warmup (JIT + filesystem caches)
    simulate_control_loop(10)

    println("Control Loop Benchmarks ($(N_LOOP_ITERS) iterations, $(N_REPEATS) repeats)")
    println("=" ^ 70)

    r = _bench(() -> simulate_control_loop(N_LOOP_ITERS), N_REPEATS)
    results["loop_1000"] = r
    per_iter = r.median / N_LOOP_ITERS

    println("  1000-iter loop          : min=$(round(r.min * 1e3; digits=2))ms  " *
            "median=$(round(r.median * 1e3; digits=2))ms")
    println("  per iteration           : $(round(per_iter * 1e6; digits=2))μs")
    println("  loop rate               : $(round(Int, 1.0 / per_iter)) iters/sec")

    # Verify convergence (controller should drive ym → 0)
    final_ym = simulate_control_loop(N_LOOP_ITERS)
    results["final_ym"] = final_ym
    println("  final ym (should → 0)   : $(round(final_ym; sigdigits=6))")

    println()
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_loop_benchmarks()
end
