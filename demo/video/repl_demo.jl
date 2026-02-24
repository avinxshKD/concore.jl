#=
repl_demo.jl -- Interactive API demo for video recording

Demonstrates the Concore.jl API in a scripted sequence suitable for
screen recording.  Can be run as a script or pasted line-by-line into
the Julia REPL.

Usage:
    julia --project=/path/to/concore-jl demo/video/repl_demo.jl
=#

using Pkg
Pkg.activate(joinpath(@__DIR__, "../.."))

using Concore

println()
println("=" ^ 58)
println("  Concore.jl API Demo")
println("=" ^ 58)

# ═════════════════════════════════════════════════════════════════════════════
# 1. Wire Format Parsing
# ═════════════════════════════════════════════════════════════════════════════

println("\n--- Wire Format Parsing ---\n")

# Standard numeric list
result = Concore.safe_parse_list("[0.0, 3.14, 2.71]")
println("  safe_parse_list(\"[0.0, 3.14, 2.71]\")")
println("  => $result")

# NumPy wrapper format (from Python controllers)
result2 = Concore.safe_parse_list("[np.float64(1.5), np.float64(2.5)]")
println()
println("  safe_parse_list(\"[np.float64(1.5), np.float64(2.5)]\")")
println("  => $result2")

# Python booleans and None
result3 = Concore.safe_parse_list("[True, False, None]")
println()
println("  safe_parse_list(\"[True, False, None]\")")
println("  => $result3")

# NumPy array wrapper
result4 = Concore.safe_parse_list("np.array([1.0, 2.0, 3.0])")
println()
println("  safe_parse_list(\"np.array([1.0, 2.0, 3.0])\")")
println("  => $result4")

# ═════════════════════════════════════════════════════════════════════════════
# 2. Initial Value Parsing
# ═════════════════════════════════════════════════════════════════════════════

println("\n--- Initial Value (initval) ---\n")

Concore.set_simtime!(0.0)

# initval extracts data portion, sets simtime from first element
u = initval("[0.0, 1.0, 2.0]")
println("  initval(\"[0.0, 1.0, 2.0]\")")
println("  => $u")
println("  simtime = $(Concore.get_simtime())")

println()

u2 = initval("[10.0, 42.0, 3.14]")
println("  initval(\"[10.0, 42.0, 3.14]\")")
println("  => $u2")
println("  simtime = $(Concore.get_simtime())")

# ═════════════════════════════════════════════════════════════════════════════
# 3. File I/O Round-Trip
# ═════════════════════════════════════════════════════════════════════════════

println("\n--- File I/O Round-Trip ---\n")

mktempdir() do dir
    # Setup directories
    out1 = joinpath(dir, "out1")
    mkpath(out1)
    # Create symlink: in1 -> out1 (simulates concore edge)
    symlink(out1, joinpath(dir, "in1"))

    # Save and override paths
    old_inpath = Concore.inpath
    old_outpath = Concore.outpath
    old_delay = Concore.get_delay()

    Concore.set_delay!(0.01)
    Concore.inpath = joinpath(dir, "in")
    Concore.outpath = joinpath(dir, "out")
    Concore.set_simtime!(5.0)

    # Write
    concore_write(1, "signal", [42.0, 3.14])
    written = read(joinpath(out1, "signal"), String)
    println("  concore_write(1, \"signal\", [42.0, 3.14])  # simtime=5.0")
    println("  File contains: $written")

    # Read back
    Concore.set_simtime!(0.0)
    Concore.s = ""
    Concore.olds = ""
    data = concore_read(1, "signal", "[0.0, 0.0, 0.0]")
    println()
    println("  concore_read(1, \"signal\", \"[0.0, 0.0, 0.0]\")")
    println("  => $data")
    println("  simtime updated to: $(Concore.get_simtime())")

    # Restore
    Concore.inpath = old_inpath
    Concore.outpath = old_outpath
    Concore.set_delay!(old_delay)
end

# ═════════════════════════════════════════════════════════════════════════════
# 4. Sync Detection (unchanged)
# ═════════════════════════════════════════════════════════════════════════════

println("\n--- Sync Detection (unchanged) ---\n")

Concore.s = ""
Concore.olds = ""

r1 = unchanged()
println("  # No reads yet")
println("  unchanged() => $r1  (true = no new data)")

Concore.s = "[1.0, 2.0]"
r2 = unchanged()
println()
println("  # After a read appends to s")
println("  unchanged() => $r2  (false = new data detected!)")

r3 = unchanged()
println()
println("  # Check again without new reads")
println("  unchanged() => $r3  (true = same data)")

# ═════════════════════════════════════════════════════════════════════════════
# 5. Backend Types
# ═════════════════════════════════════════════════════════════════════════════

println("\n--- Backend Types ---\n")

println("  FileBackend()             = $(FileBackend())")
println("  DockerBackend()           = $(DockerBackend())")
println("  SharedMemoryBackend()     = $(SharedMemoryBackend())")
println("  SharedMemoryBackend(8192) = $(SharedMemoryBackend(8192))")

# ═════════════════════════════════════════════════════════════════════════════
# 6. Context-Based API
# ═════════════════════════════════════════════════════════════════════════════

println("\n--- Context-Based API (Julia-Idiomatic) ---\n")

ctx = ConCoreContext(delay=0.01, maxtime=50)
println("  ctx = ConCoreContext(delay=0.01, maxtime=50)")
println("  => $ctx")

ctx2 = ConCoreContext(backend=SharedMemoryBackend(), delay=0.005, maxtime=200)
println()
println("  ctx = ConCoreContext(backend=SharedMemoryBackend(), delay=0.005, maxtime=200)")
println("  => $ctx2")

# ═════════════════════════════════════════════════════════════════════════════

println()
println("=" ^ 58)
println("  Demo Complete")
println("=" ^ 58)
println()
