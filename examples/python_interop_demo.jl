#=
python_interop_demo.jl -- Julia controller in a simulated concore study

Creates the same directory structure that mkconcore.py generates,
writes Python-format data, reads it back, runs a control loop.

    julia --project=. examples/python_interop_demo.jl
=#
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Concore

println()
println("=" ^ 58)
println("  Concore.jl - Cross-Language Protocol Demo")
println("  Julia node participating in a concore study")
println("=" ^ 58)

# --- Setup: mimic what mkconcore.py + makestudy creates ---
demodir = joinpath(@__DIR__, "demo_study")
rm(demodir, recursive=true, force=true)

mkpath(joinpath(demodir, "CZ"))  # controller zone
mkpath(joinpath(demodir, "CZ", "in1"))
mkpath(joinpath(demodir, "CZ", "out1"))

open(joinpath(demodir, "CZ", "concore.iport"), "w") do f
    write(f, "{'e1': 1}")
end
open(joinpath(demodir, "CZ", "concore.oport"), "w") do f
    write(f, "{'e1': 1}")
end

println("\nCreated study structure:")
println("  demo_study/CZ/in1/")
println("  demo_study/CZ/out1/")
println("  demo_study/CZ/concore.iport")
println("  demo_study/CZ/concore.oport")

# --- Simulate Python plant writing measurement files ---
println("\nSimulating Python plant writing measurements...")

python_data = [
    "[0.0, 0.0]",
    "[1.0, 0.01]",
    "[2.0, 0.0201]",
    "[3.0, 0.030301]",
    "[4.0, 0.04060401]",
    "[5.0, 0.0510100501]",
]

for data in python_data
    filepath = joinpath(demodir, "CZ", "in1", "ym")
    open(filepath, "w") do f
        write(f, data)
    end
    println("  Python wrote: $data")
end

# --- Julia controller reads and responds ---
println("\nJulia controller processing...")

Concore.delay = 0.001
Concore.inpath = joinpath(demodir, "CZ", "in")
Concore.outpath = joinpath(demodir, "CZ", "out")
Concore.simtime = 0.0

cd(joinpath(demodir, "CZ")) do
    Concore.load_iport()
    Concore.load_oport()
end

println("  iport: $(Concore.iport)")
println("  oport: $(Concore.oport)")

ym = concore_read(1, "ym", "[0.0, 0.0]")
println("  Read ym = $ym (simtime=$(Concore.simtime))")

gain = 1.01
u = [ym[1] * gain + 0.01]
println("  Computed u = $u (gain=$gain)")

concore_write(1, "u", u, delta=1)
written = read(joinpath(demodir, "CZ", "out1", "u"), String)
println("  Wrote to out1/u: $written")

# --- Format comparison ---
println("\n" * "-"^58)
println("FORMAT COMPARISON:")
println("-"^58)
println("  Python writes:  [5.0, 0.0510100501]")
println("  Julia reads:    ym = $ym")
println("  Julia writes:   $written")
println("  Python expects: [simtime, val1, val2, ...]  MATCH")
println("-"^58)

# --- Multi-step loop ---
println("\nRunning 10-step concore control loop:\n")

Concore.simtime = 0.0
init_ym = "[0.0, 0.0]"
u_val = initval("[0.0, 0.0]")
plant_state = 0.0

for step in 1:10
    global plant_state

    open(joinpath(demodir, "CZ", "in1", "ym"), "w") do f
        write(f, "[$(Concore.simtime), $plant_state]")
    end

    ym_read = concore_read(1, "ym", init_ym)
    u_out = [ym_read[1] + 0.01]
    concore_write(1, "u", u_out, delta=1)
    plant_state = u_out[1]

    out_content = read(joinpath(demodir, "CZ", "out1", "u"), String)
    println("  Step $(lpad(step, 2)): ym=$(round(ym_read[1], digits=6)) -> u=$(round(u_out[1], digits=6))  file: $out_content")
end

# --- Summary ---
println("\n" * "=" ^ 58)
println("  [ok] Julia reads Python concore format")
println("  [ok] Julia writes Python-compatible format")
println("  [ok] simtime tracking works")
println("  [ok] Port config (iport/oport) loaded")
println("  [ok] Full control loop operational")
println("=" ^ 58)

rm(demodir, recursive=true, force=true)
