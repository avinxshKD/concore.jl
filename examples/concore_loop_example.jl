#=
concore_loop_example.jl -- Full concore-style control loop

Canonical concore sync pattern (from demo/controller.py):
    u = initval(...)
    while simtime < maxtime
        while unchanged()
            ym = read(port, name, initstr)
        end
        ... compute ...
        write(port, name, u, delta=0)   # controller: delta=0
    end

The PLANT side uses the same pattern but writes with delta=1
(to advance simtime).

This example runs a simple controller + plant in one process.
In a real study these would be separate processes communicating via files.
=#
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Concore
using Concore.ConcoreUtils

println("=" ^ 60)
println("Concore.jl - Control Loop Example")
println("=" ^ 60)

# --- Setup ---
workdir = joinpath(@__DIR__, "loop_test")
mkpath(joinpath(workdir, "in1"))
mkpath(joinpath(workdir, "out1"))

Concore.delay = 0.001
Concore.inpath = joinpath(workdir, "in")
Concore.outpath = joinpath(workdir, "out")
Concore.simtime = 0.0

sim_maxtime = 10

controller = PIDNode("pid_ctrl", 2.0, 0.5, 0.1)
setpoint = 100.0

println("\nController: $(controller.id) | kp=$(controller.kp), ki=$(controller.ki), kd=$(controller.kd)")
println("Setpoint: $setpoint")
println("Max time: $sim_maxtime")

# --- Simulated concore loop ---
# In a real study, the plant would be a separate process.
# Here we simulate both sides in one process to show the pattern.
#
# NOTE: unchanged() is omitted here because both plant and controller
# run in the same process. In a real multi-process study, each node
# would use `while unchanged() ... read() ... end` to wait for fresh data.

init_ym = "[0.0, 0.0]"
u = initval("[0.0, 0.0]")
ym = 0.0

println("\n  Step | simtime |    ym    |  error   |    u")
println("  " * "-"^52)

while Concore.simtime < sim_maxtime
    global u, ym

    # plant writes measurement to controller's input
    open(joinpath(workdir, "in1", "ym"), "w") do f
        write(f, "[$(Concore.simtime), $ym]")
    end

    # controller reads measurement
    ym_vec = concore_read(1, "ym", init_ym)

    # controller computes
    error_val = setpoint - ym_vec[1]
    control_out = execute_step(controller, error_val)
    u = [control_out]

    # controller writes control signal (delta=0: controller doesn't advance time)
    concore_write(1, "u", u, delta=0)

    # plant responds (simple first-order dynamics)
    ym = ym + 0.3 * (u[1] - ym)

    # in a real study the plant writes with delta=1, advancing simtime
    Concore.simtime += 1

    step = Int(Concore.simtime)
    println("  $(lpad(step, 4)) |  $(lpad(step, 5))  | $(lpad(round(ym, digits=2), 8)) | $(lpad(round(error_val, digits=2), 8)) | $(round(u[1], digits=2))")
end

println("\n--- Loop Complete ---")
println("Final plant output: $(round(ym, digits=2))")
println("Retries: $(Concore.retrycount)")

# cleanup
rm(workdir, recursive=true, force=true)

println("\n" * "=" ^ 60)
println("Example complete!")
println("=" ^ 60)
