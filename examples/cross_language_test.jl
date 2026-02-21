#=
cross_language_test.jl -- Proves Julia <-> Python concore interoperability

This is THE demo that matters for the GSoC proposal. It shows:
1. Julia can read files written in Python concore format
2. Julia can write files that Python concore can read
3. The wire format is byte-compatible

Run: julia --project=. examples/cross_language_test.jl
=#
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Concore

println("=" ^ 60)
println("Concore.jl - Cross-Language Interoperability Test")
println("=" ^ 60)

testdir = joinpath(@__DIR__, "interop_test")
mkpath(joinpath(testdir, "in1"))
mkpath(joinpath(testdir, "out1"))

Concore.delay = 0.001
Concore.simtime = 0.0

passed = 0
failed = 0

function check(label, condition)
    global passed, failed
    if condition
        println("  PASS  $label")
        passed += 1
    else
        println("  FAIL  $label")
        failed += 1
    end
end

# =========================================================================
# Test 1: Parse Python concore.py output format
# =========================================================================
println("\n[1] Parsing Python-generated concore data:")

# these are exact strings that Python's str([...]) produces
python_outputs = [
    "[0.0, 1.0, 2.0]"         => [1.0, 2.0],
    "[5.0, 42.0, 3.14]"       => [42.0, 3.14],
    "[10, 1, 2, 3]"            => [1.0, 2.0, 3.0],
    "[0.0, 0.01]"              => [0.01],
    "[1.0, -5.5, 0.001]"      => [-5.5, 0.001],
]

for (input, expected) in python_outputs
    result = safe_parse_list(input)
    data_part = result[2:end]
    check("parse '$input' -> data=$data_part", data_part ≈ expected)
end

# =========================================================================
# Test 2: Parse NumPy-annotated data (from Python controllers)
# =========================================================================
println("\n[2] Parsing NumPy-annotated data:")

numpy_cases = [
    "[0.0, np.float64(1.5), 2.0]"     => [0.0, 1.5, 2.0],
    "[0.0, numpy.float64(3.14)]"       => [0.0, 3.14],
    "[np.int32(0), np.float64(1.0)]"   => [0.0, 1.0],
]

for (input, expected) in numpy_cases
    result = safe_parse_list(input)
    check("numpy parse '$input'", result ≈ expected)
end

# =========================================================================
# Test 3: Julia write -> readable by Python
# =========================================================================
println("\n[3] Julia write format matches Python str([...]):")

Concore.outpath = joinpath(testdir, "out")
Concore.simtime = 5.0

concore_write(1, "test_u", [42.0, 3.14])
written = read(joinpath(testdir, "out1", "test_u"), String)
println("    Julia wrote: $written")

# Python's str([5.0, 42.0, 3.14]) produces "[5.0, 42.0, 3.14]"
check("format matches Python: $written", written == "[5.0, 42.0, 3.14]")

# =========================================================================
# Test 4: Round-trip (write then read)
# =========================================================================
println("\n[4] Round-trip write -> read:")

Concore.inpath = joinpath(testdir, "out")  # read from where we wrote
Concore.simtime = 0.0

vals = concore_read(1, "test_u", "[0.0, 0.0, 0.0]")
check("round-trip values: $vals", vals ≈ [42.0, 3.14])
check("simtime updated to 5.0", Concore.simtime == 5.0)

# =========================================================================
# Test 5: initval matches Python behavior
# =========================================================================
println("\n[5] initval behavior:")

Concore.simtime = 0.0
u = initval("[10.0, 1.0, 2.0, 3.0]")
check("initval returns data portion: $u", u ≈ [1.0, 2.0, 3.0])
check("simtime set to 10.0", Concore.simtime == 10.0)

# =========================================================================
# Test 6: unchanged() sync pattern
# =========================================================================
println("\n[6] unchanged() sync:")

Concore.s = ""
Concore.olds = ""

check("no reads -> unchanged() is true", unchanged() == true)

Concore.s = "[1.0, 2.0]"
check("after read -> unchanged() is false", unchanged() == false)
check("re-check -> unchanged() is true", unchanged() == true)

# =========================================================================
# Test 7: Port config parsing
# =========================================================================
println("\n[7] Port config file parsing:")

# create a mock concore.iport file
iport_file = joinpath(testdir, "concore.iport")
open(iport_file, "w") do f
    write(f, "{'e1': 1, 'e2': 2}")
end

result = Concore.parse_port_file(iport_file)
check("iport parsed: $result", result == Dict("e1" => 1, "e2" => 2))

# =========================================================================
# Test 8: Params parsing
# =========================================================================
println("\n[8] Parameter parsing:")

params_dir = joinpath(testdir, "in1")
mkpath(params_dir)
open(joinpath(params_dir, "concore.params"), "w") do f
    write(f, "{'gain': 2.5, 'mode': 'pid'}")
end

Concore.inpath = joinpath(testdir, "in")
Concore.load_params()
check("gain param: $(tryparam("gain", 0.0))", tryparam("gain", 0.0) == 2.5)
check("mode param: $(tryparam("mode", ""))", tryparam("mode", "") == "pid")
check("missing param fallback", tryparam("nope", 99) == 99)

# =========================================================================
# Test 9: Write with delta advances simtime
# =========================================================================
println("\n[9] Delta simtime advancement:")

Concore.outpath = joinpath(testdir, "out")
Concore.simtime = 0.0
concore_write(1, "delta_test", [1.0], delta=1)
check("simtime advanced to 1.0", Concore.simtime == 1.0)
concore_write(1, "delta_test", [2.0], delta=1)
check("simtime advanced to 2.0", Concore.simtime == 2.0)

# =========================================================================
# Summary
# =========================================================================
println("\n" * "=" ^ 60)
println("Results: $passed passed, $failed failed out of $(passed + failed) tests")

if failed == 0
    println("All tests passed -- Julia concore is protocol-compatible!")
else
    println("Some tests failed -- needs investigation.")
end
println("=" ^ 60)

# cleanup
rm(testdir, recursive=true, force=true)
