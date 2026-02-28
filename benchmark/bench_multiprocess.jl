# bench_multiprocess.jl -- Multi-process IPC benchmarks
#
# Spawns separate Julia worker processes to measure real end-to-end IPC
# latency through the file-based concore protocol.  This is the most
# realistic benchmark: actual controller + plant in separate OS processes
# communicating through the filesystem.
#
# Unlike single-process simulations, this captures:
#   - OS scheduling overhead
#   - Filesystem coherence latency
#   - Process startup cost
#   - True IPC throughput
#
# For neuromodulation: this is what the actual deployment looks like.

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

# ─── Constants ───────────────────────────────────────────────────────────────

const MP_N_ITERS     = 200     # Fewer iters (multi-process is slower)
const MP_N_REPEATS   = 5
const MP_N_MESSAGES  = 1000    # For throughput measurement

# ─── Worker scripts ──────────────────────────────────────────────────────────

"""Generate a Julia script for the controller worker process."""
function _generate_controller_script(
    project_dir::String,
    ipc_dir::String,
    n_iters::Int,
    ready_file::String,
    done_file::String,
)
    return """
    # Controller worker process
    using Pkg
    Pkg.activate("$(escape_string(project_dir))")
    using Concore

    const IPC_DIR = "$(escape_string(ipc_dir))"
    const N = $(n_iters)

    # Paths
    ym_path = joinpath(IPC_DIR, "pm_to_ctrl", "ym")
    u_path  = joinpath(IPC_DIR, "ctrl_to_pm", "u")

    # Controller gain
    K = 0.5

    # Signal ready
    open("$(escape_string(ready_file))", "w") do f
        write(f, "ready")
    end

    simtime = 0.0
    for i in 1:N
        # Poll for plant output (with timeout)
        raw_ym = ""
        attempts = 0
        while isempty(raw_ym) && attempts < 1000
            try
                raw_ym = read(ym_path, String)
                # Check it's the right timestep
                if !isempty(raw_ym)
                    parsed = Concore.safe_parse_list(raw_ym)
                    if parsed[1] < simtime
                        raw_ym = ""  # stale data, keep waiting
                    end
                end
            catch
            end
            attempts += 1
            sleep(0.0001)
        end

        if isempty(raw_ym)
            break
        end

        parsed_ym = Concore.safe_parse_list(raw_ym)
        ym_val = parsed_ym[2:end]

        # Compute control signal
        u_val = [-K * ym_val[1]]

        # Write u
        wire_u = Concore._format_wire(vcat(simtime + 1.0, u_val))
        open(u_path, "w") do f
            write(f, wire_u)
        end

        simtime += 1.0
    end

    # Signal done
    open("$(escape_string(done_file))", "w") do f
        write(f, string(simtime))
    end
    """
end

"""Generate a Julia script for the plant worker process."""
function _generate_plant_script(
    project_dir::String,
    ipc_dir::String,
    n_iters::Int,
    ready_file::String,
    done_file::String,
)
    return """
    # Plant worker process
    using Pkg
    Pkg.activate("$(escape_string(project_dir))")
    using Concore

    const IPC_DIR = "$(escape_string(ipc_dir))"
    const N = $(n_iters)

    # Paths
    ym_path = joinpath(IPC_DIR, "pm_to_ctrl", "ym")
    u_path  = joinpath(IPC_DIR, "ctrl_to_pm", "u")

    # Plant model: ym_next = A * ym + B * u
    A = 0.9
    B = 0.1

    ym = [1.0]
    simtime = 0.0

    # Signal ready
    open("$(escape_string(ready_file))", "w") do f
        write(f, "ready")
    end

    for i in 1:N
        # Write ym for controller
        wire_ym = Concore._format_wire(vcat(simtime, ym))
        open(ym_path, "w") do f
            write(f, wire_ym)
        end

        # Poll for control signal
        raw_u = ""
        attempts = 0
        while isempty(raw_u) && attempts < 1000
            try
                raw_u = read(u_path, String)
                if !isempty(raw_u)
                    parsed = Concore.safe_parse_list(raw_u)
                    if parsed[1] < simtime + 1.0
                        raw_u = ""  # stale data
                    end
                end
            catch
            end
            attempts += 1
            sleep(0.0001)
        end

        if isempty(raw_u)
            break
        end

        parsed_u = Concore.safe_parse_list(raw_u)
        u_read = parsed_u[2:end]

        # Update plant state
        ym = [A * ym[1] + B * u_read[1]]
        simtime += 1.0
    end

    # Signal done with final value
    open("$(escape_string(done_file))", "w") do f
        write(f, string(ym[1]))
    end
    """
end

# ─── Multi-process loop ─────────────────────────────────────────────────────

"""
Run a multi-process controller+plant loop.

Spawns two Julia processes that communicate through files in `ipc_dir`.
Returns (elapsed_time, final_ym) or (NaN, NaN) on failure.
"""
function run_multiprocess_loop(n_iters::Int)
    project_dir = abspath(joinpath(@__DIR__, ".."))
    ipc_dir = mktempdir()

    # Create IPC directories
    mkpath(joinpath(ipc_dir, "pm_to_ctrl"))
    mkpath(joinpath(ipc_dir, "ctrl_to_pm"))

    # Create coordination files
    ctrl_ready = joinpath(ipc_dir, "ctrl_ready")
    pm_ready   = joinpath(ipc_dir, "pm_ready")
    ctrl_done  = joinpath(ipc_dir, "ctrl_done")
    pm_done    = joinpath(ipc_dir, "pm_done")

    # Write worker scripts
    ctrl_script_path = joinpath(ipc_dir, "controller.jl")
    pm_script_path   = joinpath(ipc_dir, "plant.jl")

    ctrl_code = _generate_controller_script(project_dir, ipc_dir, n_iters, ctrl_ready, ctrl_done)
    pm_code   = _generate_plant_script(project_dir, ipc_dir, n_iters, pm_ready, pm_done)

    open(ctrl_script_path, "w") do f
        write(f, ctrl_code)
    end
    open(pm_script_path, "w") do f
        write(f, pm_code)
    end

    elapsed = NaN
    final_ym = NaN

    try
        # Launch both processes
        t_start = time()

        julia_exe = joinpath(Sys.BINDIR, "julia")
        ctrl_proc = run(`$julia_exe --startup-file=no --project=$project_dir $ctrl_script_path`; wait=false)
        pm_proc   = run(`$julia_exe --startup-file=no --project=$project_dir $pm_script_path`; wait=false)

        # Wait for both to complete (with timeout)
        timeout = 120.0  # 2 minutes
        while (process_running(ctrl_proc) || process_running(pm_proc)) &&
              (time() - t_start) < timeout
            sleep(0.1)
        end

        elapsed = time() - t_start

        # Kill if still running
        if process_running(ctrl_proc)
            kill(ctrl_proc)
        end
        if process_running(pm_proc)
            kill(pm_proc)
        end

        # Read results
        if isfile(pm_done)
            try
                final_ym = parse(Float64, read(pm_done, String))
            catch
            end
        end
    catch e
        @warn "Multi-process benchmark failed" exception=(e, catch_backtrace())
    finally
        rm(ipc_dir; recursive=true, force=true)
    end

    return (elapsed=elapsed, final_ym=final_ym)
end

# ─── Message throughput ──────────────────────────────────────────────────────

"""
Measure message passing throughput between single-process simulated IPC.

This measures how fast messages can flow through the file-based protocol
without the overhead of process spawning. Used as a comparison baseline
for the multi-process benchmark.
"""
function bench_single_process_throughput(n_messages::Int)
    dir = mktempdir()
    path_a = joinpath(dir, "a_to_b")
    path_b = joinpath(dir, "b_to_a")
    mkpath(dirname(path_a))
    mkpath(dirname(path_b))

    # Touch files
    open(path_a, "w") do f; write(f, ""); end
    open(path_b, "w") do f; write(f, ""); end

    val = [0.0, 1.0, 2.0]

    t = @elapsed begin
        for i in 1:n_messages
            # A writes
            wire = Concore._format_wire(vcat(Float64(i), val))
            open(path_a, "w") do f
                write(f, wire)
            end
            # B reads
            raw = read(path_a, String)
            Concore.safe_parse_list(raw)
            # B writes response
            wire_b = Concore._format_wire(vcat(Float64(i), val))
            open(path_b, "w") do f
                write(f, wire_b)
            end
            # A reads response
            raw_b = read(path_b, String)
            Concore.safe_parse_list(raw_b)
        end
    end

    rm(dir; recursive=true, force=true)
    return t
end

# ─── Run benchmarks ─────────────────────────────────────────────────────────

function run_multiprocess_benchmarks()
    results = Dict{String, Any}()

    println("Multi-Process IPC Benchmarks")
    println("=" ^ 70)

    # ── Single-process baseline ──────────────────────────────────────
    println()
    println("  Single-Process Message Throughput (baseline)")
    println("  " * "-" ^ 50)

    # Warmup
    bench_single_process_throughput(10)

    sp_time = bench_single_process_throughput(MP_N_MESSAGES)
    sp_rate = MP_N_MESSAGES / sp_time
    results["single_process_throughput_ops_sec"] = sp_rate
    results["single_process_time"] = sp_time
    println("    $(MP_N_MESSAGES) round-trip messages : $(round(sp_time * 1e3; digits=2))ms")
    println("    Throughput               : $(round(Int, sp_rate)) round-trips/sec")
    println("    Per message (round-trip) : $(round(sp_time / MP_N_MESSAGES * 1e6; digits=2))μs")

    # ── Multi-process loop ───────────────────────────────────────────
    println()
    println("  Multi-Process Control Loop ($(MP_N_ITERS) iters)")
    println("  " * "-" ^ 50)

    # Check if Julia binary is available for spawning
    julia_exe = joinpath(Sys.BINDIR, "julia")
    julia_available = isfile(julia_exe)

    if julia_available
        # Warmup run
        println("    Warmup run...")
        run_multiprocess_loop(10)

        mp_times = Vector{Float64}(undef, MP_N_REPEATS)
        mp_final_yms = Vector{Float64}(undef, MP_N_REPEATS)

        for rep in 1:MP_N_REPEATS
            result = run_multiprocess_loop(MP_N_ITERS)
            mp_times[rep] = result.elapsed
            mp_final_yms[rep] = result.final_ym
            println("    Run $rep/$(MP_N_REPEATS): $(round(result.elapsed * 1e3; digits=1))ms  " *
                    "final_ym=$(round(result.final_ym; sigdigits=4))")
        end

        sort!(mp_times)
        mp_median = mp_times[div(MP_N_REPEATS + 1, 2)]
        mp_min = mp_times[1]
        mp_per_iter = mp_median / MP_N_ITERS

        results["multiprocess_loop"] = (; min=mp_min, median=mp_median)
        results["multiprocess_per_iter"] = mp_per_iter
        results["multiprocess_final_ym"] = mp_final_yms[end]

        println()
        println("    Summary:")
        println("      Min total time        : $(round(mp_min * 1e3; digits=2))ms")
        println("      Median total time     : $(round(mp_median * 1e3; digits=2))ms")
        println("      Per iteration         : $(round(mp_per_iter * 1e3; digits=3))ms")
        println("      Loop rate             : $(round(Int, 1.0 / mp_per_iter)) iters/sec")

        # Comparison with single-process
        println()
        println("  Single-Process vs Multi-Process Comparison")
        println("  " * "-" ^ 50)

        # Run equivalent single-process loop for fair comparison
        # (simulate_control_loop from bench_loop.jl uses same algorithm)
        sp_loop_time = @elapsed begin
            dir = mktempdir()
            ctrl_out = joinpath(dir, "ctrl_out")
            pm_out = joinpath(dir, "pm_out")
            mkpath(ctrl_out)
            mkpath(pm_out)
            K = 0.5; A = 0.9; B = 0.1
            simtime = 0.0; ym = [1.0]
            u_path = joinpath(ctrl_out, "u")
            ym_path = joinpath(pm_out, "ym")
            for i in 1:MP_N_ITERS
                ym_wire = Concore._format_wire(vcat(simtime, ym))
                open(ym_path, "w") do f; write(f, ym_wire); end
                raw_ym = read(ym_path, String)
                parsed_ym = Concore.safe_parse_list(raw_ym)
                ym_val = parsed_ym[2:end]
                u_val = [-K * ym_val[1]]
                u_wire = Concore._format_wire(vcat(simtime, u_val))
                open(u_path, "w") do f; write(f, u_wire); end
                raw_u = read(u_path, String)
                parsed_u = Concore.safe_parse_list(raw_u)
                u_read = parsed_u[2:end]
                ym = [A * ym_val[1] + B * u_read[1]]
                simtime += 1.0
            end
            rm(dir; recursive=true, force=true)
        end

        results["single_process_loop_time"] = sp_loop_time
        sp_per_iter = sp_loop_time / MP_N_ITERS

        println("    Single-process $(MP_N_ITERS)-iter loop : $(round(sp_loop_time * 1e3; digits=2))ms  " *
                "($(round(sp_per_iter * 1e6; digits=2))μs/iter)")
        println("    Multi-process  $(MP_N_ITERS)-iter loop : $(round(mp_median * 1e3; digits=2))ms  " *
                "($(round(mp_per_iter * 1e3; digits=3))ms/iter)")
        overhead = mp_per_iter / sp_per_iter
        results["ipc_overhead_ratio"] = overhead
        println("    IPC overhead ratio       : $(round(overhead; digits=1))x")
        println("    NOTE: Multi-process overhead is dominated by OS scheduling")
        println("          and filesystem coherence, not Julia compute overhead.")
    else
        println("    Julia binary not found at: $(julia_exe)")
        println("    Skipping multi-process benchmarks (requires Julia runtime)")
        println("    Single-process throughput still available above.")
    end

    println()
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_multiprocess_benchmarks()
end
