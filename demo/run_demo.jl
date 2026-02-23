#=
run_demo.jl -- Multi-process end-to-end demo orchestrator

Sets up the concore directory structure, creates symlinks and config files,
then launches controller.jl and pm.jl as separate Julia processes.

Usage:
    julia demo/run_demo.jl [maxtime]

Default maxtime is 15 (small for a quick test).
=#

const DEMO_DIR  = @__DIR__
const PKG_ROOT  = dirname(DEMO_DIR)

# Parse optional maxtime argument
const MAXTIME = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 15

println("=" ^ 60)
println("Concore.jl Multi-Process Demo")
println("=" ^ 60)
println("  Package root : $PKG_ROOT")
println("  Max time     : $MAXTIME")
println()

# ─────────────────────────────────────────────────────────────
# 1. Create a temporary workspace
# ─────────────────────────────────────────────────────────────
const WORK_DIR = mktempdir(; cleanup=true)
println("[1/5] Workspace: $WORK_DIR")

# Edge directories (shared data channels)
const CU_DIR  = joinpath(WORK_DIR, "CU")
const PYM_DIR = joinpath(WORK_DIR, "PYM")

# Node directories (each process's working directory)
const CZ_DIR = joinpath(WORK_DIR, "CZ")
const PZ_DIR = joinpath(WORK_DIR, "PZ")

for d in [CU_DIR, PYM_DIR, CZ_DIR, PZ_DIR]
    mkpath(d)
end

# ─────────────────────────────────────────────────────────────
# 2. Create symlinks for the concore port layout
# ─────────────────────────────────────────────────────────────
# Controller node CZ:
#   in1  -> PYM (reads ym from plant)
#   out1 -> CU  (writes u to plant)
# Plant model node PZ:
#   in1  -> CU  (reads u from controller)
#   out1 -> PYM (writes ym to controller)
println("[2/5] Creating symlinks...")

symlink(PYM_DIR, joinpath(CZ_DIR, "in1"))
symlink(CU_DIR,  joinpath(CZ_DIR, "out1"))
symlink(CU_DIR,  joinpath(PZ_DIR, "in1"))
symlink(PYM_DIR, joinpath(PZ_DIR, "out1"))

# ─────────────────────────────────────────────────────────────
# 3. Create concore config files
# ─────────────────────────────────────────────────────────────
println("[3/5] Writing config files...")

# Port configs (edge name -> port number)
write(joinpath(CZ_DIR, "concore.iport"), "{'ym': 1}")
write(joinpath(CZ_DIR, "concore.oport"), "{'u': 1}")
write(joinpath(PZ_DIR, "concore.iport"), "{'u': 1}")
write(joinpath(PZ_DIR, "concore.oport"), "{'ym': 1}")

# Write initial data files so the first read succeeds
write(joinpath(PYM_DIR, "ym"), "[0.0, 0.0]")
write(joinpath(CU_DIR, "u"),   "[0.0, 0.0]")

# Write maxtime into the in1/ directory (where default_maxtime! looks)
write(joinpath(CZ_DIR, "in1", "concore.maxtime"), string(MAXTIME))
write(joinpath(PZ_DIR, "in1", "concore.maxtime"), string(MAXTIME))

# ─────────────────────────────────────────────────────────────
# 4. Launch controller and plant model as separate processes
# ─────────────────────────────────────────────────────────────
println("[4/5] Launching Julia processes...")

controller_script = joinpath(DEMO_DIR, "controller.jl")
pm_script         = joinpath(DEMO_DIR, "pm.jl")

julia_cmd = Base.julia_cmd()

# Launch both processes
controller_proc = run(
    pipeline(
        Cmd(`$julia_cmd --project=$PKG_ROOT $controller_script`; dir=CZ_DIR),
        stdout = stdout,
        stderr = stderr,
    );
    wait = false,
)

pm_proc = run(
    pipeline(
        Cmd(`$julia_cmd --project=$PKG_ROOT $pm_script`; dir=PZ_DIR),
        stdout = stdout,
        stderr = stderr,
    );
    wait = false,
)

println("  Controller PID: $(getpid(controller_proc))")
println("  Plant model PID: $(getpid(pm_proc))")
println()

# ─────────────────────────────────────────────────────────────
# 5. Wait for completion
# ─────────────────────────────────────────────────────────────
println("[5/5] Waiting for processes to complete...")

# Wait with a timeout
const TIMEOUT_SEC = 120  # 2 minutes should be plenty for 15 cycles

timer = Timer(TIMEOUT_SEC) do t
    if process_running(controller_proc)
        println("TIMEOUT: killing controller")
        kill(controller_proc)
    end
    if process_running(pm_proc)
        println("TIMEOUT: killing plant model")
        kill(pm_proc)
    end
end

wait(controller_proc)
wait(pm_proc)
close(timer)

c_exit = controller_proc.exitcode
p_exit = pm_proc.exitcode

println()
println("=" ^ 60)
if c_exit == 0 && p_exit == 0
    println("SUCCESS: Both processes completed normally.")
else
    println("FAILURE:")
    c_exit != 0 && println("  Controller exited with code $c_exit")
    p_exit != 0 && println("  Plant model exited with code $p_exit")
end
println("=" ^ 60)

# Return appropriate exit code
exit(c_exit == 0 && p_exit == 0 ? 0 : 1)
