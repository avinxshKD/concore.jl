#=
plotym.jl -- Plotting observer node for concore demo

Julia equivalent of the Python example/plotym.py.
Reads ym values, accumulates history, and plots at the end.

Requires Plots.jl to be installed.

Run from the node working directory:
    julia --project=/path/to/concore-jl /path/to/concore-jl/demo/plotym.jl
=#

# Make the Concore package findable
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using Concore

Concore.delay = 0.02
Concore.default_maxtime!(150)

init_simtime_u  = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

ymt = Vector{Vector{Float64}}()
ym = initval(init_simtime_ym)

while Concore.simtime < Concore.maxtime
    while unchanged()
        ym = concore_read(1, "ym", init_simtime_ym)
    end
    concore_write(1, "ym", ym)
    println("ym=$(ym)")
    push!(ymt, copy(ym))
end

println("retry=$(Concore.retrycount)")

# Extract first component for plotting
ym1 = [x[1] for x in ymt]
Nsim = length(ym1)

# Only attempt plotting if Plots is available
try
    using Plots
    p = plot(1:Nsim, ym1;
        ylabel = "ym",
        xlabel = "Cycles",
        label  = "ym",
        legend = :topright,
    )
    savefig(p, "ym.pdf")
    println("Plot saved to ym.pdf")
    display(p)
catch e
    if isa(e, ArgumentError) || isa(e, LoadError)
        println("Plots.jl not available -- skipping plot generation.")
        println("Install with: using Pkg; Pkg.add(\"Plots\")")
    else
        rethrow(e)
    end
end
