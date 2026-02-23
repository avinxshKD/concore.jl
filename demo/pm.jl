#=
pm.jl -- Plant model node for concore demo

Julia equivalent of the Python demo/pm.py.

Run from the node working directory (e.g., PZ/):
    julia --project=/path/to/concore-jl /path/to/concore-jl/demo/pm.jl
=#

# Make the Concore package findable
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using Concore

"""
    pm(u) -> Vector{Float64}

Simple plant model: adds 0.01 to input.
"""
function pm(u::Vector{Float64})::Vector{Float64}
    return u .+ 0.01
end

Concore.default_maxtime!(150)
Concore.delay = 0.02

init_simtime_u  = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

ym = initval(init_simtime_ym)
u  = initval(init_simtime_u)

while Concore.simtime < Concore.maxtime
    while unchanged()
        u = concore_read(1, "u", init_simtime_u)
    end
    ym = pm(u)
    println("$(Concore.simtime). u=$(u) ym=$(ym)")
    concore_write(1, "ym", ym; delta=1)
end

println("retry=$(Concore.retrycount)")
