@testset "Docker Backend" begin

    # =========================================================================
    # Type hierarchy
    # =========================================================================

    @testset "type hierarchy" begin

        @testset "DockerBackend is subtype of AbstractBackend" begin
            @test DockerBackend <: AbstractBackend
        end

        @testset "FileBackend is subtype of AbstractBackend" begin
            @test FileBackend <: AbstractBackend
        end

        @testset "DockerBackend constructor" begin
            b = DockerBackend()
            @test b isa DockerBackend
            @test b isa AbstractBackend
        end

        @testset "FileBackend constructor" begin
            b = FileBackend()
            @test b isa FileBackend
        end

    end

    # =========================================================================
    # detect_environment
    # =========================================================================

    @testset "detect_environment" begin

        @testset "returns FileBackend when not in Docker" begin
            # We're running tests locally, /in1 should not exist
            backend = detect_environment()
            @test backend isa FileBackend
        end

        @testset "return type is AbstractBackend" begin
            backend = detect_environment()
            @test backend isa AbstractBackend
        end

    end

    # =========================================================================
    # Path helpers
    # =========================================================================

    @testset "path helpers" begin

        @testset "_backend_inpath for FileBackend" begin
            @test Concore._backend_inpath(FileBackend()) == "./in"
        end

        @testset "_backend_outpath for FileBackend" begin
            @test Concore._backend_outpath(FileBackend()) == "./out"
        end

        @testset "_backend_inpath for DockerBackend" begin
            @test Concore._backend_inpath(DockerBackend()) == "/in"
        end

        @testset "_backend_outpath for DockerBackend" begin
            @test Concore._backend_outpath(DockerBackend()) == "/out"
        end

        @testset "_backend_inpath for SharedMemoryBackend" begin
            @test Concore._backend_inpath(SharedMemoryBackend()) == "./in"
        end

        @testset "_backend_outpath for SharedMemoryBackend" begin
            @test Concore._backend_outpath(SharedMemoryBackend()) == "./out"
        end

    end

    # =========================================================================
    # indir / outdir with context
    # =========================================================================

    @testset "indir / outdir" begin

        @testset "indir with FileBackend" begin
            ctx = ConCoreContext()
            @test Concore.indir(ctx, 1) == "./in1"
            @test Concore.indir(ctx, 2) == "./in2"
            @test Concore.indir(ctx, 10) == "./in10"
        end

        @testset "outdir with FileBackend" begin
            ctx = ConCoreContext()
            @test Concore.outdir(ctx, 1) == "./out1"
            @test Concore.outdir(ctx, 2) == "./out2"
        end

        @testset "indir with DockerBackend" begin
            ctx = ConCoreContext(backend = DockerBackend())
            @test Concore.indir(ctx, 1) == "/in1"
            @test Concore.indir(ctx, 2) == "/in2"
        end

        @testset "outdir with DockerBackend" begin
            ctx = ConCoreContext(backend = DockerBackend())
            @test Concore.outdir(ctx, 1) == "/out1"
            @test Concore.outdir(ctx, 2) == "/out2"
        end

    end

    # =========================================================================
    # init_docker! (context-based)
    # =========================================================================

    @testset "init_docker! context" begin

        @testset "switches context to DockerBackend" begin
            ctx = ConCoreContext()
            @test ctx.backend isa FileBackend
            init_docker!(ctx)
            @test ctx.backend isa DockerBackend
        end

        @testset "returns the context" begin
            ctx = ConCoreContext()
            result = init_docker!(ctx)
            @test result === ctx
        end

        @testset "paths change after init_docker!" begin
            ctx = ConCoreContext()
            @test Concore.indir(ctx, 1) == "./in1"
            init_docker!(ctx)
            @test Concore.indir(ctx, 1) == "/in1"
            @test Concore.outdir(ctx, 1) == "/out1"
        end

    end

    # =========================================================================
    # init_docker! (module-global)
    # =========================================================================

    @testset "init_docker! module-global" begin

        @testset "changes module-level inpath and outpath" begin
            # Save original values
            old_backend = Concore._backend
            old_inpath = Concore.inpath
            old_outpath = Concore.outpath

            init_docker!()

            @test Concore._backend isa DockerBackend
            @test Concore.inpath == "/in"
            @test Concore.outpath == "/out"

            # Restore original values
            Concore._backend = old_backend
            Concore.inpath = old_inpath
            Concore.outpath = old_outpath
        end

        @testset "returns nothing" begin
            old_backend = Concore._backend
            old_inpath = Concore.inpath
            old_outpath = Concore.outpath

            result = init_docker!()
            @test result === nothing

            Concore._backend = old_backend
            Concore.inpath = old_inpath
            Concore.outpath = old_outpath
        end

    end

    # =========================================================================
    # Context-based write/read with DockerBackend (path verification)
    # =========================================================================

    @testset "DockerBackend context paths" begin

        @testset "context with DockerBackend uses absolute paths" begin
            ctx = ConCoreContext(backend = DockerBackend())
            @test Concore.indir(ctx, 1) == "/in1"
            @test Concore.outdir(ctx, 1) == "/out1"
            @test Concore.indir(ctx, 3) == "/in3"
            @test Concore.outdir(ctx, 3) == "/out3"
        end

        @testset "context with FileBackend uses relative paths" begin
            ctx = ConCoreContext(backend = FileBackend())
            @test Concore.indir(ctx, 1) == "./in1"
            @test Concore.outdir(ctx, 1) == "./out1"
        end

    end

    # =========================================================================
    # ConCoreContext with backends
    # =========================================================================

    @testset "ConCoreContext backend field" begin

        @testset "default backend is FileBackend" begin
            ctx = ConCoreContext()
            @test ctx.backend isa FileBackend
        end

        @testset "can set DockerBackend" begin
            ctx = ConCoreContext(backend = DockerBackend())
            @test ctx.backend isa DockerBackend
        end

        @testset "can set SharedMemoryBackend" begin
            ctx = ConCoreContext(backend = SharedMemoryBackend())
            @test ctx.backend isa SharedMemoryBackend
        end

        @testset "backend field is mutable" begin
            ctx = ConCoreContext()
            @test ctx.backend isa FileBackend
            ctx.backend = DockerBackend()
            @test ctx.backend isa DockerBackend
            ctx.backend = SharedMemoryBackend(8192)
            @test ctx.backend isa SharedMemoryBackend
        end

    end

end
