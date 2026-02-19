#=
test_wire_compat.jl -- Wire format compatibility test

Verifies that Julia's concore wire format is 100% compatible with Python's.

Tests:
  1. Julia write produces exact Python-compatible output
  2. Python-style output (including numpy wrappers) is correctly parsed
  3. Round-trip: Julia write -> parse -> verify

Usage:
    julia test/integration/test_wire_compat.jl
=#

const TEST_DIR = @__DIR__
const REPO_ROOT = dirname(dirname(TEST_DIR))

push!(LOAD_PATH, REPO_ROOT)
using Concore

# ═════════════════════════════════════════════════════════════════════════════
# Test harness
# ═════════════════════════════════════════════════════════════════════════════

mutable struct TestResult
    passed::Int
    failed::Int
    total::Int
end

TestResult() = TestResult(0, 0, 0)

function check(r::TestResult, name::String, cond::Bool)
    r.total += 1
    if cond
        r.passed += 1
        println("  PASS: $name")
    else
        r.failed += 1
        println("  FAIL: $name")
    end
end

# ═════════════════════════════════════════════════════════════════════════════
# Tests
# ═════════════════════════════════════════════════════════════════════════════

function run_wire_compat_tests()
    r = TestResult()

    println("=" ^ 60)
    println("Wire Format Compatibility Tests")
    println("=" ^ 60)

    # ── Section 1: Julia write format ────────────────────────────────────
    println("\n--- Julia write produces Python-compatible output ---")

    mktempdir() do dir
        # Save and restore state
        old_outpath = Concore.outpath
        old_simtime = Concore.simtime
        old_delay = Concore.delay
        Concore.delay = 0.0

        # Test: integer floats
        Concore.outpath = joinpath(dir, "out")
        Concore.simtime = 0.0
        Concore.concore_write(1, "test_int", [1.0, 2.0, 3.0])
        content = read(joinpath(dir, "out1", "test_int"), String)
        check(r, "integer floats: [0.0, 1.0, 2.0, 3.0]", content == "[0.0, 1.0, 2.0, 3.0]")

        # Test: mixed floats
        Concore.simtime = 5.0
        Concore.concore_write(1, "test_mix", [3.14, -1.5, 0.0])
        content = read(joinpath(dir, "out1", "test_mix"), String)
        check(r, "wire starts with [5.0", startswith(content, "[5.0, "))
        check(r, "wire is parseable", startswith(content, "[") && endswith(content, "]"))
        parsed = Concore.safe_parse_list(content)
        check(r, "simtime preserved", parsed[1] == 5.0)
        check(r, "value 3.14 preserved", abs(parsed[2] - 3.14) < 1e-10)
        check(r, "value -1.5 preserved", parsed[3] == -1.5)
        check(r, "value 0.0 preserved", parsed[4] == 0.0)

        # Test: zero values (common initial state)
        Concore.simtime = 0.0
        Concore.concore_write(1, "test_zero", [0.0, 0.0])
        content = read(joinpath(dir, "out1", "test_zero"), String)
        check(r, "zero values: [0.0, 0.0, 0.0]", content == "[0.0, 0.0, 0.0]")

        # Test: single value
        Concore.simtime = 10.0
        Concore.concore_write(1, "test_single", [42.0])
        content = read(joinpath(dir, "out1", "test_single"), String)
        check(r, "single value: [10.0, 42.0]", content == "[10.0, 42.0]")

        # Restore
        Concore.outpath = old_outpath
        Concore.simtime = old_simtime
        Concore.delay = old_delay
    end

    # ── Section 2: Parse Python-style output ─────────────────────────────
    println("\n--- Parse Python-style output ---")

    # Standard Python list
    v = Concore.safe_parse_list("[0.0, 1.0, 2.0]")
    check(r, "Python [0.0, 1.0, 2.0]", v == [0.0, 1.0, 2.0])

    # Python integers
    v = Concore.safe_parse_list("[0, 1, 2]")
    check(r, "Python [0, 1, 2]", v == [0.0, 1.0, 2.0])

    # Python booleans
    v = Concore.safe_parse_list("[True, False]")
    check(r, "Python [True, False]", v == [1.0, 0.0])

    # Python None
    v = Concore.safe_parse_list("[None, 0.0]")
    check(r, "Python [None, 0.0]", v == [0.0, 0.0])

    # Numpy float64 wrappers
    v = Concore.safe_parse_list("[np.float64(5.0), np.float64(42.0)]")
    check(r, "np.float64 wrappers", v == [5.0, 42.0])

    # Numpy array wrapper
    v = Concore.safe_parse_list("np.array([1.0, 2.0, 3.0])")
    check(r, "np.array wrapper", v == [1.0, 2.0, 3.0])

    # Mixed numpy wrappers
    v = Concore.safe_parse_list("[np.float64(0.0), np.int32(1), numpy.float32(2.5)]")
    check(r, "mixed numpy wrappers", v == [0.0, 1.0, 2.5])

    # Negative values
    v = Concore.safe_parse_list("[-1.5, 0.001, -100.0]")
    check(r, "negative values", v ≈ [-1.5, 0.001, -100.0])

    # Scientific notation
    v = Concore.safe_parse_list("[0.0, 1e-12, 1e12]")
    check(r, "scientific notation", v[2] ≈ 1e-12 && v[3] ≈ 1e12)

    # Whitespace variations
    v = Concore.safe_parse_list("  [  1.0 ,  2.0  ]  ")
    check(r, "extra whitespace", v == [1.0, 2.0])

    # ── Section 3: Round-trip compatibility ──────────────────────────────
    println("\n--- Round-trip: Julia write -> file -> Julia read ---")

    mktempdir() do dir
        old_outpath = Concore.outpath
        old_inpath = Concore.inpath
        old_simtime = Concore.simtime
        old_delay = Concore.delay
        old_s = Concore.s
        old_olds = Concore.olds
        Concore.delay = 0.0
        Concore.s = ""
        Concore.olds = ""

        # Write data
        Concore.outpath = joinpath(dir, "data")
        Concore.simtime = 7.0
        Concore.concore_write(1, "signal", [1.5, -2.5, 0.0])

        # Read it back
        Concore.inpath = joinpath(dir, "data")
        Concore.simtime = 0.0
        result = Concore.concore_read(1, "signal", "[0.0, 0.0, 0.0, 0.0]")

        check(r, "round-trip: simtime restored to 7.0", Concore.simtime == 7.0)
        check(r, "round-trip: 3 data values", length(result) == 3)
        check(r, "round-trip: value 1.5", abs(result[1] - 1.5) < 1e-10)
        check(r, "round-trip: value -2.5", abs(result[2] - (-2.5)) < 1e-10)
        check(r, "round-trip: value 0.0", result[3] == 0.0)

        # Restore
        Concore.outpath = old_outpath
        Concore.inpath = old_inpath
        Concore.simtime = old_simtime
        Concore.delay = old_delay
        Concore.s = old_s
        Concore.olds = old_olds
    end

    # ── Section 4: Python concore.write compatibility ────────────────────
    println("\n--- Verify Julia matches Python concore.write output ---")

    # Python's concore.write for [0.0, 0.0] with simtime=0 produces: [0.0, 0.0, 0.0]
    # Python's str([0.0, 0.0, 0.0]) = "[0.0, 0.0, 0.0]"
    mktempdir() do dir
        old_outpath = Concore.outpath
        old_simtime = Concore.simtime
        old_delay = Concore.delay
        Concore.delay = 0.0
        Concore.outpath = joinpath(dir, "out")

        # Simulate what Python would write for initial state
        Concore.simtime = 0.0
        Concore.concore_write(1, "u", [0.0])
        content = read(joinpath(dir, "out1", "u"), String)
        check(r, "matches Python: [0.0, 0.0]", content == "[0.0, 0.0]")

        # Simulate what Python would write at simtime=5 with value 42.0
        Concore.simtime = 5.0
        Concore.concore_write(1, "u", [42.0])
        content = read(joinpath(dir, "out1", "u"), String)
        check(r, "matches Python: [5.0, 42.0]", content == "[5.0, 42.0]")

        # With delta=1
        Concore.simtime = 5.0
        Concore.concore_write(1, "ym", [3.01]; delta=1)
        content = read(joinpath(dir, "out1", "ym"), String)
        # simtime + delta = 6.0
        parsed = Concore.safe_parse_list(content)
        check(r, "delta=1: simtime becomes 6.0", parsed[1] == 6.0)
        check(r, "delta=1: value preserved", abs(parsed[2] - 3.01) < 1e-10)

        Concore.outpath = old_outpath
        Concore.simtime = old_simtime
        Concore.delay = old_delay
    end

    # ── Summary ──────────────────────────────────────────────────────────
    println("\n" * "=" ^ 60)
    println("Results: $(r.passed) passed, $(r.failed) failed, $(r.total) total")
    if r.failed == 0
        println("PASS: All wire format compatibility tests passed.")
    else
        println("FAIL: $(r.failed) test(s) failed.")
    end
    println("=" ^ 60)

    return r.failed == 0
end

# Run and exit with appropriate code
success = run_wire_compat_tests()
exit(success ? 0 : 1)
