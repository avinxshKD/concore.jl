#=
controller.jl -- Bang-bang controller node for cross-language demo

Julia controller that communicates with a Python plant model via concore
file-based IPC. Uses the standalone concore.jl module (no package install).

Run from the node working directory (e.g., CZ/):
    julia controller.jl
=#

include("concore.jl")
using .Concore

# Setpoint
const ysp = 3.0

"""
    controller(ym) -> Vector{Float64}

Bang-bang controller: if measurement is below setpoint, increase by 1%;
otherwise decrease by 10%.
"""
function controller(ym::Vector{Float64})::Vector{Float64}
    if ym[1] < ysp
        return 1.01 .* ym
    else
        return 0.9 .* ym
    end
end

Concore.default_maxtime!(150)
Concore.delay = 0.02

init_simtime_u  = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

u  = initval(init_simtime_u)
ym = initval(init_simtime_ym)

while Concore.simtime < Concore.maxtime
    while unchanged()
        ym = concore_read(1, "ym", init_simtime_ym)
    end
    u = controller(ym)
    println("$(Concore.simtime). u=$(u) ym=$(ym)")
    concore_write(1, "u", u; delta=0)
end

println("retry=$(Concore.retrycount)")
