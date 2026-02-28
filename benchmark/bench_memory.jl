# bench_memory.jl -- Memory allocation benchmarks
#
# Measures heap allocations per operation using Julia's @allocated macro.
# This is one of Julia's superpowers: the ability to achieve zero-allocation
# hot paths, eliminating GC pressure entirely for real-time control loops.
#
# Python allocates on every operation (interpreter overhead, object creation).
# Julia's type-stable, compiled code can avoid allocations completely on
# repeated calls — critical for neuromodulation where GC pauses are lethal
# to real-time guarantees.

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

# ─── Allocation measurement helper ──────────────────────────────────────────

"""
Measure allocations for `f()` over `n` calls.

Returns (min_bytes, mean_bytes, median_bytes) of per-call allocations.
The first call is always excluded (JIT compilation allocates).
"""
function _measure_allocs(f, n::Int)
    # Warmup: ensure JIT compilation is done
    f()
    f()

    allocs = Vector{Int}(undef, n)
    for i in 1:n
        allocs[i] = @allocated f()
    end
    sort!(allocs)
    mn = minimum(allocs)
    avg = sum(allocs) / n
    med = allocs[div(n + 1, 2)]
    return (; min_bytes=mn, mean_bytes=avg, median_bytes=med)
end

"""Format bytes in a human-readable way."""
function _fmt_bytes(bytes)
    if bytes == 0
        return "0 bytes (zero-alloc!)"
    elseif bytes < 1024
        return "$(round(Int, bytes)) bytes"
    elseif bytes < 1024 * 1024
        return "$(round(bytes / 1024; digits=2)) KiB"
    else
        return "$(round(bytes / (1024 * 1024); digits=2)) MiB"
    end
end

# ─── Test inputs ─────────────────────────────────────────────────────────────

const MEM_SMALL_INPUT  = "[0.0, 1.0]"
const MEM_MEDIUM_INPUT = "[0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]"
const MEM_LARGE_INPUT  = "[0.0, " * join(["$i.0" for i in 1:100], ", ") * "]"

const MEM_FORMAT_SMALL  = [0.0, 1.0]
const MEM_FORMAT_MEDIUM = collect(0.0:9.0)
const MEM_FORMAT_LARGE  = vcat(0.0, collect(1.0:100.0))

const MEM_N_ITERS = 1_000

# ─── Run benchmarks ─────────────────────────────────────────────────────────

function run_memory_benchmarks()
    results = Dict{String, Any}()

    # Warmup everything
    Concore.safe_parse_list(MEM_SMALL_INPUT)
    Concore.safe_parse_list(MEM_MEDIUM_INPUT)
    Concore.safe_parse_list(MEM_LARGE_INPUT)
    Concore._format_wire(MEM_FORMAT_SMALL)
    Concore._format_wire(MEM_FORMAT_MEDIUM)
    Concore._format_wire(MEM_FORMAT_LARGE)

    println("Memory Allocation Benchmarks ($(MEM_N_ITERS) samples each)")
    println("=" ^ 70)

    # ── Parse allocations ─────────────────────────────────────────────
    println()
    println("  Parse Allocations (bytes per call)")
    println("  " * "-" ^ 50)

    a = _measure_allocs(() -> Concore.safe_parse_list(MEM_SMALL_INPUT), MEM_N_ITERS)
    results["parse_small_alloc"] = a
    println("    parse small  (2 elem)   : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    a = _measure_allocs(() -> Concore.safe_parse_list(MEM_MEDIUM_INPUT), MEM_N_ITERS)
    results["parse_medium_alloc"] = a
    println("    parse medium (10 elem)  : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    a = _measure_allocs(() -> Concore.safe_parse_list(MEM_LARGE_INPUT), MEM_N_ITERS)
    results["parse_large_alloc"] = a
    println("    parse large  (101 elem) : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    # ── Format allocations ────────────────────────────────────────────
    println()
    println("  Format Allocations (bytes per call)")
    println("  " * "-" ^ 50)

    a = _measure_allocs(() -> Concore._format_wire(MEM_FORMAT_SMALL), MEM_N_ITERS)
    results["format_small_alloc"] = a
    println("    format small  (2 elem)  : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    a = _measure_allocs(() -> Concore._format_wire(MEM_FORMAT_MEDIUM), MEM_N_ITERS)
    results["format_medium_alloc"] = a
    println("    format medium (10 elem) : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    a = _measure_allocs(() -> Concore._format_wire(MEM_FORMAT_LARGE), MEM_N_ITERS)
    results["format_large_alloc"] = a
    println("    format large  (101 elem): min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    # ── Read/Write cycle allocations ──────────────────────────────────
    println()
    println("  Read/Write Cycle Allocations")
    println("  " * "-" ^ 50)

    dir = mktempdir()
    outd = joinpath(dir, "out1")
    ind  = joinpath(dir, "in1")
    mkpath(outd)
    mkpath(ind)

    # Pre-create the file for read
    signal_path = joinpath(ind, "signal")
    wire = Concore._format_wire([0.0, 42.0, 3.14])
    open(signal_path, "w") do f
        write(f, wire)
    end

    # File write allocation
    out_path = joinpath(outd, "signal")
    function _do_file_write()
        val = [0.0, 42.0, 3.14]
        w = Concore._format_wire(val)
        open(out_path, "w") do f
            write(f, w)
        end
    end
    a = _measure_allocs(_do_file_write, MEM_N_ITERS)
    results["file_write_alloc"] = a
    println("    file write cycle        : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    # File read+parse allocation
    function _do_file_read()
        raw = read(signal_path, String)
        Concore.safe_parse_list(raw)
    end
    a = _measure_allocs(_do_file_read, MEM_N_ITERS)
    results["file_read_alloc"] = a
    println("    file read+parse         : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    # Full write+copy+read cycle
    function _do_full_cycle()
        val = [0.0, 42.0, 3.14]
        w = Concore._format_wire(val)
        open(out_path, "w") do f
            write(f, w)
        end
        cp(out_path, signal_path; force=true)
        raw = read(signal_path, String)
        Concore.safe_parse_list(raw)
    end
    a = _measure_allocs(_do_full_cycle, MEM_N_ITERS)
    results["full_cycle_alloc"] = a
    println("    full write+read cycle   : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")

    # ── SHM allocation comparison ────────────────────────────────────
    println()
    println("  SHM vs File Allocation Comparison")
    println("  " * "-" ^ 50)

    shm_path = joinpath(outd, "shm_signal")

    # SHM write allocation
    function _do_shm_write()
        val = [0.0, 42.0, 3.14]
        w = Concore._format_wire(val)
        wb = Vector{UInt8}(w)
        wlen = length(wb)
        io = Concore._get_or_create_segment(shm_path, 4096)
        seekstart(io)
        buf = Mmap.mmap(io, Vector{UInt8}, 4096)
        buf[1:wlen] .= wb[1:wlen]
        buf[wlen+1] = 0x00
        Mmap.sync!(buf)
        finalize(buf)
    end
    # Warmup
    _do_shm_write()
    a = _measure_allocs(_do_shm_write, MEM_N_ITERS)
    results["shm_write_alloc"] = a
    println("    SHM write               : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")
    println("    File write              : min=$(_fmt_bytes(results["file_write_alloc"].min_bytes))  " *
            "median=$(_fmt_bytes(results["file_write_alloc"].median_bytes))")

    # SHM read allocation
    shm_read_path = joinpath(ind, "shm_signal")
    open(shm_read_path, "w") do f
        write(f, wire)
    end

    function _do_shm_read()
        io = Concore._get_or_create_segment(shm_read_path, 4096)
        seekstart(io)
        buf = Mmap.mmap(io, Vector{UInt8}, 4096)
        nullpos = findfirst(iszero, buf)
        data_end = nullpos === nothing ? length(buf) : nullpos - 1
        raw = data_end > 0 ? String(buf[1:data_end]) : ""
        finalize(buf)
        Concore.safe_parse_list(raw)
    end
    _do_shm_read()
    a = _measure_allocs(_do_shm_read, MEM_N_ITERS)
    results["shm_read_alloc"] = a
    println("    SHM read+parse          : min=$(_fmt_bytes(a.min_bytes))  " *
            "median=$(_fmt_bytes(a.median_bytes))")
    println("    File read+parse         : min=$(_fmt_bytes(results["file_read_alloc"].min_bytes))  " *
            "median=$(_fmt_bytes(results["file_read_alloc"].median_bytes))")

    # ── Allocation summary ───────────────────────────────────────────
    println()
    println("  Allocation Summary")
    println("  " * "-" ^ 50)

    total_parse_min = results["parse_small_alloc"].min_bytes +
                      results["parse_medium_alloc"].min_bytes +
                      results["parse_large_alloc"].min_bytes
    total_format_min = results["format_small_alloc"].min_bytes +
                       results["format_medium_alloc"].min_bytes +
                       results["format_large_alloc"].min_bytes

    println("    Total parse alloc (all sizes)  : $(_fmt_bytes(total_parse_min))")
    println("    Total format alloc (all sizes) : $(_fmt_bytes(total_format_min))")
    println("    Python equivalent              : ~10-100x more (interpreter overhead)")
    println("    NOTE: Julia's @allocated measures heap allocations only.")
    println("          Stack allocations (common in hot paths) are FREE.")

    println()

    # Cleanup
    Concore.shm_cleanup()
    rm(dir; recursive=true, force=true)

    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_memory_benchmarks()
end
