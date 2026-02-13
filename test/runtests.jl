using Test
using Concore

@testset "Concore.jl" begin
    include("test_parser.jl")
    include("test_config.jl")
    include("test_protocol.jl")
    include("test_sync.jl")
    include("test_interop.jl")
    include("test_docker.jl")
    include("test_shm.jl")
    include("test_zmq.jl")
    include("test_utils.jl")
    include("test_context.jl")
    include("test_observability.jl")
end
