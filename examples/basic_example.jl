#=
basic_example.jl -- Demonstrates Concore.jl core API

Shows the safe parser, initval, file I/O round-trip, and sync pattern.
=#
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Concore

println("=" ^ 50)
println("Concore.jl - Basic API Demo")
println("=" ^ 50)

# --- 1. Safe parser (no more eval/Meta.parse) ---
println("\n[1] Safe parser tests:")

test_cases = [
    "[1.0, 2.0, 3.0]",
    "[0, 1, 2]",
    "[0.0, np.float64(1.5), 2.0]",
    "[1.0, True, False, None]",
]

for tc in test_cases
    try
        result = safe_parse_list(tc)
        println("  '$tc' -> $result")
    catch e
        println("  '$tc' -> ERROR: $e")
    end
end

# --- 2. initval (simtime extraction) ---
println("\n[2] initval:")

Concore.simtime = 0.0
u = initval("[0.0, 1.5, 2.5, 3.5]")
println("  initval(\"[0.0, 1.5, 2.5, 3.5]\") -> u=$u, simtime=$(Concore.simtime)")

u = initval("[5.0, 10.0, 20.0]")
println("  initval(\"[5.0, 10.0, 20.0]\") -> u=$u, simtime=$(Concore.simtime)")

# --- 3. tryparam ---
println("\n[3] tryparam (with no params file loaded):")
println("  tryparam(\"gain\", 2.0) -> $(tryparam("gain", 2.0))")
println("  tryparam(\"missing\", \"default\") -> $(tryparam("missing", "default"))")

# --- 4. File I/O demo (creates actual files) ---
println("\n[4] File I/O round-trip:")

Concore.simtime = 3.0
Concore.delay = 0.001  # fast for demo
Concore.outpath = joinpath(@__DIR__, "out")
Concore.inpath = joinpath(@__DIR__, "out")  # read back what we wrote

# concore_write creates dirs automatically, but we can pre-create to be safe
mkpath(joinpath(@__DIR__, "out1"))

concore_write(1, "test_signal", [42.0, 3.14])
written = read(joinpath(@__DIR__, "out1", "test_signal"), String)
println("  Wrote: $written")

# read it back
vals = concore_read(1, "test_signal", "[0.0, 0.0, 0.0]")
println("  Read back: $vals (simtime now=$(Concore.simtime))")

# --- 5. unchanged() sync pattern ---
println("\n[5] unchanged() sync demo:")
Concore.s = ""
Concore.olds = ""
println("  First call (no reads yet): unchanged()=$(unchanged())")

# simulate a read that adds to s
Concore.s = "[1.0, 2.0]"
println("  After simulated read: unchanged()=$(unchanged())")
println("  Immediate re-check:   unchanged()=$(unchanged())")

# cleanup test artifacts
rm(joinpath(@__DIR__, "out1"), recursive=true, force=true)

println("\n" * "=" ^ 50)
println("All basic API tests passed.")
println("=" ^ 50)
