# bench_shm.jl -- Shared memory backend benchmarks
#
# Measures SHM (memory-mapped file) performance vs the standard file backend.
# This demonstrates Julia's ability to leverage mmap for low-latency IPC --
# a capability that Python cannot easily match.
#
# Benchmarks:
#   - SHM write/read cycle latency
#   - SHM throughput (ops/sec)
#   - SHM vs File backend comparison
#   - SHM control loop simulation

# Load Concore from the project root
if !isdefined(Main, :Concore)
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using Concore
end

using Mmap

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

const SHM_N_SINGLE     = 5_000
const SHM_N_THROUGHPUT = 10_000
const SHM_N_LOOP_ITERS = 1000
const SHM_N_REPEATS    = 10

# ─── SHM write + read cycle ─────────────────────────────────────────────────

"""Single SHM write + read cycle (mmap-backed, no sleep/retry)."""
function bench_shm_write_read(dir::String)
    indir  = joinpath(dir, "in1")
    outdir = joinpath(dir, "out1")

    val = [0.0, 42.0, 3.14]
    wire = Concore._format_wire(val)
    filepath = joinpath(outdir, "signal")

    # SHM Write: mmap the file and write
    io = Concore._get_or_create_segment(filepath, 4096)
    seekstart(io)
    buf = Mmap.mmap(io, Vector{UInt8}, 4096)
    wire_bytes = Vector{UInt8}(wire)
    n = length(wire_bytes)
    buf[1:n] .= wire_bytes[1:n]
    buf[n+1] = 0x00
    if n + 2 <= 4096
        buf[n+2:min(n+64, 4096)] .= 0x00  # partial zero for speed
    end
    Mmap.sync!(buf)
    finalize(buf)

    # Copy to input side (simulating IPC)
    inpath = joinpath(indir, "signal")
    cp(filepath, inpath; force=true)

    # SHM Read: mmap and extract
    io_in = Concore._get_or_create_segment(inpath, 4096)
    seekstart(io_in)
    buf_in = Mmap.mmap(io_in, Vector{UInt8}, 4096)
    nullpos = findfirst(iszero, buf_in)
    data_end = nullpos === nothing ? length(buf_in) : nullpos - 1
    raw = data_end > 0 ? String(buf_in[1:data_end]) : ""
    finalize(buf_in)

    parsed = Concore.safe_parse_list(raw)
    return parsed
end

"""Single File write + read cycle (for comparison)."""
function bench_file_write_read(dir::String)
    indir  = joinpath(dir, "in1")
    outdir = joinpath(dir, "out1")

    val = [0.0, 42.0, 3.14]
    wire = Concore._format_wire(val)
    filepath = joinpath(outdir, "signal")

    open(filepath, "w") do f
        write(f, wire)
    end

    inpath = joinpath(indir, "signal")
    cp(filepath, inpath; force=true)

    raw = read(inpath, String)
    parsed = Concore.safe_parse_list(raw)
    return parsed
end

# ─── SHM throughput ──────────────────────────────────────────────────────────

"""SHM write throughput: repeated mmap writes."""
function bench_shm_write_throughput(dir::String, n::Int)
    outdir = joinpath(dir, "out1")
    filepath = joinpath(outdir, "signal")
    val = [0.0, 1.0, 2.0, 3.0, 4.0]
    wire = Concore._format_wire(val)
    wire_bytes = Vector{UInt8}(wire)
    wb_len = length(wire_bytes)

    io = Concore._get_or_create_segment(filepath, 4096)

    t = @elapsed begin
        for _ in 1:n
            seekstart(io)
            buf = Mmap.mmap(io, Vector{UInt8}, 4096)
            buf[1:wb_len] .= wire_bytes[1:wb_len]
            buf[wb_len+1] = 0x00
            Mmap.sync!(buf)
            finalize(buf)
        end
    end
    return t
end

"""SHM read throughput: repeated mmap reads + parse."""
function bench_shm_read_throughput(dir::String, n::Int)
    indir = joinpath(dir, "in1")
    filepath = joinpath(indir, "signal")

    # Pre-write data
    val = [0.0, 1.0, 2.0, 3.0, 4.0]
    wire = Concore._format_wire(val)
    open(filepath, "w") do f
        write(f, wire)
    end

    io = Concore._get_or_create_segment(filepath, 4096)

    t = @elapsed begin
        for _ in 1:n
            seekstart(io)
            buf = Mmap.mmap(io, Vector{UInt8}, 4096)
            nullpos = findfirst(iszero, buf)
            data_end = nullpos === nothing ? length(buf) : nullpos - 1
            raw = data_end > 0 ? String(buf[1:data_end]) : ""
            finalize(buf)
            Concore.safe_parse_list(raw)
        end
    end
    return t
end

"""File write throughput (for comparison)."""
function bench_file_write_throughput(dir::String, n::Int)
    outdir = joinpath(dir, "out1")
    filepath = joinpath(outdir, "signal")
    val = [0.0, 1.0, 2.0, 3.0, 4.0]
    wire = Concore._format_wire(val)

    t = @elapsed begin
        for _ in 1:n
            open(filepath, "w") do f
                write(f, wire)
            end
        end
    end
    return t
end

"""File read throughput (for comparison)."""
function bench_file_read_throughput(dir::String, n::Int)
    indir = joinpath(dir, "in1")
    filepath = joinpath(indir, "signal")

    # Pre-write data
    val = [0.0, 1.0, 2.0, 3.0, 4.0]
    wire = Concore._format_wire(val)
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

# ─── SHM control loop simulation ────────────────────────────────────────────

"""
Simulate a controller+PM loop for `n_iters` iterations using SHM.

Same as bench_loop.jl but uses mmap-backed reads/writes instead of
regular file I/O — demonstrating the SHM backend's lower latency.
"""
function simulate_shm_control_loop(n_iters::Int)
    dir = mktempdir()
    ctrl_out = joinpath(dir, "ctrl_out")
    pm_out = joinpath(dir, "pm_out")
    mkpath(ctrl_out)
    mkpath(pm_out)

    K = 0.5
    A = 0.9
    B = 0.1
    simtime = 0.0
    ym = [1.0]
    seg_size = 4096

    u_path  = joinpath(ctrl_out, "u")
    ym_path = joinpath(pm_out, "ym")

    for i in 1:n_iters
        # --- Plant writes ym via SHM ---
        ym_wire = Concore._format_wire(vcat(simtime, ym))
        ym_bytes = Vector{UInt8}(ym_wire)
        ym_len = length(ym_bytes)

        io_ym = Concore._get_or_create_segment(ym_path, seg_size)
        seekstart(io_ym)
        buf_ym = Mmap.mmap(io_ym, Vector{UInt8}, seg_size)
        buf_ym[1:ym_len] .= ym_bytes[1:ym_len]
        buf_ym[ym_len+1] = 0x00
        Mmap.sync!(buf_ym)
        finalize(buf_ym)

        # --- Controller reads ym via SHM ---
        seekstart(io_ym)
        buf_ym_r = Mmap.mmap(io_ym, Vector{UInt8}, seg_size)
        nullpos = findfirst(iszero, buf_ym_r)
        data_end = nullpos === nothing ? length(buf_ym_r) : nullpos - 1
        raw_ym = data_end > 0 ? String(buf_ym_r[1:data_end]) : ""
        finalize(buf_ym_r)
        parsed_ym = Concore.safe_parse_list(raw_ym)
        ym_val = parsed_ym[2:end]

        # Controller computes u
        u_val = [-K * ym_val[1]]

        # --- Controller writes u via SHM ---
        u_wire = Concore._format_wire(vcat(simtime, u_val))
        u_bytes = Vector{UInt8}(u_wire)
        u_len = length(u_bytes)

        io_u = Concore._get_or_create_segment(u_path, seg_size)
        seekstart(io_u)
        buf_u = Mmap.mmap(io_u, Vector{UInt8}, seg_size)
        buf_u[1:u_len] .= u_bytes[1:u_len]
        buf_u[u_len+1] = 0x00
        Mmap.sync!(buf_u)
        finalize(buf_u)

        # --- Plant reads u via SHM ---
        seekstart(io_u)
        buf_u_r = Mmap.mmap(io_u, Vector{UInt8}, seg_size)
        nullpos_u = findfirst(iszero, buf_u_r)
        data_end_u = nullpos_u === nothing ? length(buf_u_r) : nullpos_u - 1
        raw_u = data_end_u > 0 ? String(buf_u_r[1:data_end_u]) : ""
        finalize(buf_u_r)
        parsed_u = Concore.safe_parse_list(raw_u)
        u_read = parsed_u[2:end]

        # Plant computes next ym
        ym = [A * ym_val[1] + B * u_read[1]]
        simtime += 1.0
    end

    Concore.shm_cleanup()
    rm(dir; recursive=true, force=true)
    return ym[1]
end

# ─── Run benchmarks ─────────────────────────────────────────────────────────

function run_shm_benchmarks()
    results = Dict{String, Any}()

    dir = mktempdir()
    indir  = joinpath(dir, "in1")
    outdir = joinpath(dir, "out1")
    mkpath(indir)
    mkpath(outdir)

    # Warmup
    bench_shm_write_read(dir)
    bench_file_write_read(dir)
    simulate_shm_control_loop(10)

    println("Shared Memory (SHM) Benchmarks")
    println("=" ^ 70)

    # ── Single write+read comparison ──────────────────────────────────
    println()
    println("  Write+Read Cycle Latency")
    println("  " * "-" ^ 50)

    r_shm = _bench(() -> bench_shm_write_read(dir), SHM_N_SINGLE)
    results["shm_single_write_read"] = r_shm
    println("    SHM write+read        : min=$(round(r_shm.min * 1e6; digits=2))μs  " *
            "median=$(round(r_shm.median * 1e6; digits=2))μs")

    r_file = _bench(() -> bench_file_write_read(dir), SHM_N_SINGLE)
    results["file_single_write_read"] = r_file
    println("    File write+read       : min=$(round(r_file.min * 1e6; digits=2))μs  " *
            "median=$(round(r_file.median * 1e6; digits=2))μs")

    if r_shm.median > 0 && r_file.median > 0
        speedup = r_file.median / r_shm.median
        println("    SHM speedup           : $(round(speedup; digits=2))x faster")
    end

    # ── Throughput comparison ─────────────────────────────────────────
    println()
    println("  Throughput ($(SHM_N_THROUGHPUT) ops)")
    println("  " * "-" ^ 50)

    # SHM write
    shm_wt = bench_shm_write_throughput(dir, SHM_N_THROUGHPUT)
    shm_wps = SHM_N_THROUGHPUT / shm_wt
    results["shm_write_throughput_ops_sec"] = shm_wps
    println("    SHM write throughput  : $(round(Int, shm_wps)) ops/sec")

    # File write
    file_wt = bench_file_write_throughput(dir, SHM_N_THROUGHPUT)
    file_wps = SHM_N_THROUGHPUT / file_wt
    results["file_write_throughput_ops_sec"] = file_wps
    println("    File write throughput : $(round(Int, file_wps)) ops/sec")

    if file_wps > 0 && shm_wps > 0
        println("    Write speedup         : $(round(shm_wps / file_wps; digits=2))x")
    end

    # SHM read
    shm_rt = bench_shm_read_throughput(dir, SHM_N_THROUGHPUT)
    shm_rps = SHM_N_THROUGHPUT / shm_rt
    results["shm_read_throughput_ops_sec"] = shm_rps
    println("    SHM read+parse        : $(round(Int, shm_rps)) ops/sec")

    # File read
    file_rt = bench_file_read_throughput(dir, SHM_N_THROUGHPUT)
    file_rps = SHM_N_THROUGHPUT / file_rt
    results["file_read_throughput_ops_sec"] = file_rps
    println("    File read+parse       : $(round(Int, file_rps)) ops/sec")

    if file_rps > 0 && shm_rps > 0
        println("    Read speedup          : $(round(shm_rps / file_rps; digits=2))x")
    end

    # ── SHM control loop ─────────────────────────────────────────────
    println()
    println("  SHM Control Loop ($(SHM_N_LOOP_ITERS) iters, $(SHM_N_REPEATS) repeats)")
    println("  " * "-" ^ 50)

    r_loop = _bench(() -> simulate_shm_control_loop(SHM_N_LOOP_ITERS), SHM_N_REPEATS)
    results["shm_loop_1000"] = r_loop
    per_iter = r_loop.median / SHM_N_LOOP_ITERS
    println("    SHM 1000-iter loop    : min=$(round(r_loop.min * 1e3; digits=2))ms  " *
            "median=$(round(r_loop.median * 1e3; digits=2))ms")
    println("    Per iteration         : $(round(per_iter * 1e6; digits=2))μs")
    println("    Loop rate             : $(round(Int, 1.0 / per_iter)) iters/sec")

    final_ym = simulate_shm_control_loop(SHM_N_LOOP_ITERS)
    results["shm_final_ym"] = final_ym
    println("    Final ym (should → 0) : $(round(final_ym; sigdigits=6))")

    println()

    # Cleanup
    Concore.shm_cleanup()
    rm(dir; recursive=true, force=true)

    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_shm_benchmarks()
end
