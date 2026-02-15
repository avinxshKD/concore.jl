@testset "Context-based API" begin

    # Helper to create a fresh context with zero delay for fast tests
    function make_test_ctx(; backend=FileBackend(), delay=0.0, maxtime=100)
        ConCoreContext(backend=backend, delay=delay, maxtime=maxtime)
    end

    # =========================================================================
    # ConCoreContext constructor
    # =========================================================================

    @testset "ConCoreContext constructor" begin

        @testset "default constructor" begin
            ctx = ConCoreContext()
            @test ctx.s == ""
            @test ctx.olds == ""
            @test ctx.delay == 1.0
            @test ctx.retrycount == 0
            @test ctx.simtime == 0.0
            @test ctx.maxtime == 100
            @test isempty(ctx.iport)
            @test isempty(ctx.oport)
            @test isempty(ctx.params)
            @test ctx.backend isa FileBackend
        end

        @testset "keyword constructor" begin
            ctx = ConCoreContext(delay=0.01, maxtime=50)
            @test ctx.delay == 0.01
            @test ctx.maxtime == 50
            @test ctx.backend isa FileBackend
        end

        @testset "constructor with custom backend" begin
            ctx = ConCoreContext(backend=DockerBackend())
            @test ctx.backend isa DockerBackend
        end

        @testset "constructor with SharedMemoryBackend" begin
            ctx = ConCoreContext(backend=SharedMemoryBackend(8192))
            @test ctx.backend isa SharedMemoryBackend
            @test ctx.backend.segment_size == 8192
        end

        @testset "context is mutable" begin
            ctx = ConCoreContext()
            @test ismutable(ctx)
            ctx.simtime = 42.0
            @test ctx.simtime == 42.0
            ctx.delay = 0.5
            @test ctx.delay == 0.5
        end

        @testset "show method works" begin
            ctx = ConCoreContext()
            s = sprint(show, ctx)
            @test occursin("ConCoreContext", s)
            @test occursin("FileBackend", s)
        end

    end

    # =========================================================================
    # Context-based initval
    # =========================================================================

    @testset "initval (context)" begin

        @testset "parses simtime and returns data portion" begin
            ctx = make_test_ctx()
            result = initval(ctx, "[0.0, 1.5, 2.5]")
            @test result == [1.5, 2.5]
            @test ctx.simtime == 0.0
        end

        @testset "sets simtime from first element" begin
            ctx = make_test_ctx()
            initval(ctx, "[10.0, 42.0]")
            @test ctx.simtime == 10.0
        end

        @testset "single value (simtime only)" begin
            ctx = make_test_ctx()
            result = initval(ctx, "[5.0]")
            @test isempty(result)
            @test ctx.simtime == 5.0
        end

        @testset "multiple data values" begin
            ctx = make_test_ctx()
            result = initval(ctx, "[0.0, 1.0, 2.0, 3.0, 4.0, 5.0]")
            @test result == [1.0, 2.0, 3.0, 4.0, 5.0]
            @test length(result) == 5
        end

    end

    # =========================================================================
    # Context-based unchanged
    # =========================================================================

    @testset "unchanged (context)" begin

        @testset "returns true when s and olds are both empty" begin
            ctx = make_test_ctx()
            @test unchanged(ctx) == true
        end

        @testset "returns false when s has new data" begin
            ctx = make_test_ctx()
            ctx.s = "some data"
            @test unchanged(ctx) == false
            @test ctx.olds == "some data"
        end

        @testset "returns true on second call without new data" begin
            ctx = make_test_ctx()
            ctx.s = "data"
            unchanged(ctx)  # false, sets olds = "data"

            # Now s == olds == "data"
            # unchanged should reset s to "" and return true
            @test unchanged(ctx) == true
            @test ctx.s == ""
        end

        @testset "cycle: write data, detect change, then unchanged" begin
            ctx = make_test_ctx()

            # Initially unchanged
            @test unchanged(ctx) == true

            # Simulate a read appending to s
            ctx.s = "new_read_data"
            @test unchanged(ctx) == false

            # No new reads — s == olds
            @test unchanged(ctx) == true
            @test ctx.s == ""
        end

    end

    # =========================================================================
    # Context-based concore_write and concore_read
    # =========================================================================

    @testset "concore_write (context)" begin

        @testset "creates file with correct wire format" begin
            mktempdir() do dir
                ctx = make_test_ctx()
                ctx.simtime = 5.0

                # We need to temporarily make outdir point to our tempdir
                # outdir(ctx, 1) == _backend_outpath(ctx.backend) * "1" == "./out1"
                # So we work in the tempdir as working directory or write directly
                outpath = joinpath(dir, "out1")
                mkpath(outpath)
                filepath = joinpath(outpath, "test_signal")

                # Use context-based write with a workaround:
                # We'll create the dir structure and verify the function works
                # by pointing to an actual path

                # Direct file-based test: write to the expected path
                outval = vcat(ctx.simtime + 0, [42.0, 3.14])
                wire = Concore._format_wire(outval)
                mkpath(dirname(filepath))
                open(filepath, "w") do f
                    write(f, wire)
                end

                content = read(filepath, String)
                @test content == "[5.0, 42.0, 3.14]"
            end
        end

        @testset "context-based write creates directory and file" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    ctx.simtime = 2.0

                    concore_write(ctx, 1, "signal", [10.0, 20.0])

                    filepath = joinpath("./out1", "signal")
                    @test isfile(filepath)
                    content = read(filepath, String)
                    @test content == "[2.0, 10.0, 20.0]"
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "delta=0 does not advance simtime" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    ctx.simtime = 10.0

                    concore_write(ctx, 1, "test", [1.0]; delta=0)
                    @test ctx.simtime == 10.0
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "delta=1 advances simtime" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    ctx.simtime = 10.0

                    concore_write(ctx, 1, "test", [1.0]; delta=1)
                    @test ctx.simtime == 11.0
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "writes empty value array (simtime only)" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    ctx.simtime = 3.0

                    concore_write(ctx, 1, "test", Float64[])

                    content = read(joinpath("./out1", "test"), String)
                    @test content == "[3.0]"
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "string write variant" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    concore_write(ctx, 1, "raw", "[99.0, 1.0]")

                    content = read(joinpath("./out1", "raw"), String)
                    @test content == "[99.0, 1.0]"
                finally
                    cd(old_dir)
                end
            end
        end

    end

    @testset "concore_read (context)" begin

        @testset "reads data and extracts values after simtime" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    mkpath("./in1")
                    write("./in1/signal", "[5.0, 42.0, 3.14]")

                    result = concore_read(ctx, 1, "signal", "[0.0, 0.0, 0.0]")
                    @test result == [42.0, 3.14]
                    @test ctx.simtime == 5.0
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "falls back to initstr when file missing" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    result = concore_read(ctx, 1, "nofile", "[0.0, 1.0, 2.0]")
                    @test result == [1.0, 2.0]
                    @test ctx.simtime == 0.0
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "simtime uses max (doesn't go backwards)" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    ctx.simtime = 20.0
                    mkpath("./in1")
                    write("./in1/signal", "[5.0, 1.0]")

                    concore_read(ctx, 1, "signal", "[0.0, 0.0]")
                    @test ctx.simtime == 20.0  # stays at 20
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "accumulates into s string for sync" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    mkpath("./in1")
                    write("./in1/signal", "[0.0, 1.0]")

                    @test ctx.s == ""
                    concore_read(ctx, 1, "signal", "[0.0, 0.0]")
                    @test ctx.s != ""
                finally
                    cd(old_dir)
                end
            end
        end

    end

    # =========================================================================
    # Context-based write-read round-trip
    # =========================================================================

    @testset "context write-read round-trip" begin

        @testset "data survives round-trip" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    ctx.simtime = 5.0

                    original = [42.0, 3.14, -1.5]
                    concore_write(ctx, 1, "roundtrip", original)

                    # Reset for reading
                    ctx2 = make_test_ctx()
                    # Point in to the same place as out
                    # outdir is ./out1, indir is ./in1 — need to symlink or copy
                    mkpath("./in1")
                    cp(joinpath("./out1", "roundtrip"), joinpath("./in1", "roundtrip"))

                    result = concore_read(ctx2, 1, "roundtrip", "[0.0, 0.0, 0.0, 0.0]")
                    @test result ≈ original
                    @test ctx2.simtime == 5.0
                finally
                    cd(old_dir)
                end
            end
        end

    end

    # =========================================================================
    # Multiple independent contexts (isolation)
    # =========================================================================

    @testset "context isolation" begin

        @testset "two contexts have independent simtime" begin
            ctx1 = make_test_ctx()
            ctx2 = make_test_ctx()

            ctx1.simtime = 10.0
            ctx2.simtime = 20.0

            @test ctx1.simtime == 10.0
            @test ctx2.simtime == 20.0
        end

        @testset "two contexts have independent delay" begin
            ctx1 = ConCoreContext(delay=0.01)
            ctx2 = ConCoreContext(delay=0.5)

            @test ctx1.delay == 0.01
            @test ctx2.delay == 0.5
        end

        @testset "two contexts have independent s/olds" begin
            ctx1 = make_test_ctx()
            ctx2 = make_test_ctx()

            ctx1.s = "data1"
            ctx2.s = "data2"

            @test ctx1.s == "data1"
            @test ctx2.s == "data2"
        end

        @testset "two contexts have independent backends" begin
            ctx1 = ConCoreContext(backend=FileBackend())
            ctx2 = ConCoreContext(backend=DockerBackend())

            @test ctx1.backend isa FileBackend
            @test ctx2.backend isa DockerBackend
        end

        @testset "two contexts have independent port mappings" begin
            ctx1 = make_test_ctx()
            ctx2 = make_test_ctx()

            ctx1.iport["ym"] = 1
            ctx2.iport["sensor"] = 2

            @test haskey(ctx1.iport, "ym")
            @test !haskey(ctx1.iport, "sensor")
            @test haskey(ctx2.iport, "sensor")
            @test !haskey(ctx2.iport, "ym")
        end

        @testset "two contexts have independent params" begin
            ctx1 = make_test_ctx()
            ctx2 = make_test_ctx()

            ctx1.params["gain"] = 2.5
            ctx2.params["mode"] = "auto"

            @test ctx1.params["gain"] == 2.5
            @test !haskey(ctx1.params, "mode")
            @test ctx2.params["mode"] == "auto"
            @test !haskey(ctx2.params, "gain")
        end

    end

    # =========================================================================
    # Context-based concore_init!
    # =========================================================================

    @testset "concore_init! (context)" begin

        @testset "initializes without error when no config files" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    # Should not throw even without config files
                    concore_init!(ctx)
                    @test isempty(ctx.iport)
                    @test isempty(ctx.oport)
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "loads iport from config file" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    write("concore.iport", "{'ym': 1, 'ref': 2}")
                    ctx = make_test_ctx()
                    concore_init!(ctx)
                    @test ctx.iport["ym"] == 1
                    @test ctx.iport["ref"] == 2
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "loads oport from config file" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    write("concore.oport", "{'u': 1}")
                    ctx = make_test_ctx()
                    concore_init!(ctx)
                    @test ctx.oport["u"] == 1
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "loads maxtime from config file" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    mkpath("./in1")
                    write("./in1/concore.maxtime", "200")
                    ctx = make_test_ctx()
                    concore_init!(ctx)
                    @test ctx.maxtime == 200
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "loads params from config file (dict format)" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    mkpath("./in1")
                    write("./in1/concore.params", "{'gain': 2.5, 'mode': 'auto'}")
                    ctx = make_test_ctx()
                    concore_init!(ctx)
                    @test ctx.params["gain"] == 2.5
                    @test ctx.params["mode"] == "auto"
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "loads params from key=value format" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    mkpath("./in1")
                    write("./in1/concore.params", "gain=3.0;mode=manual")
                    ctx = make_test_ctx()
                    concore_init!(ctx)
                    @test ctx.params["gain"] == 3.0
                    @test ctx.params["mode"] == "manual"
                finally
                    cd(old_dir)
                end
            end
        end

        @testset "returns the context" begin
            mktempdir() do dir
                old_dir = pwd()
                cd(dir)
                try
                    ctx = make_test_ctx()
                    result = concore_init!(ctx)
                    @test result === ctx
                finally
                    cd(old_dir)
                end
            end
        end

    end

    # =========================================================================
    # tryparam (context)
    # =========================================================================

    @testset "tryparam (context)" begin

        @testset "returns param value if exists" begin
            ctx = make_test_ctx()
            ctx.params["gain"] = 2.5
            @test tryparam(ctx, "gain", 1.0) == 2.5
        end

        @testset "returns default if not found" begin
            ctx = make_test_ctx()
            @test tryparam(ctx, "missing", 99.0) == 99.0
        end

        @testset "returns string param" begin
            ctx = make_test_ctx()
            ctx.params["mode"] = "auto"
            @test tryparam(ctx, "mode", "manual") == "auto"
        end

    end

    # =========================================================================
    # _format_wire
    # =========================================================================

    @testset "_format_wire" begin

        @testset "formats integer-valued floats with .0 suffix" begin
            @test Concore._format_wire([0.0]) == "[0.0]"
            @test Concore._format_wire([5.0, 42.0]) == "[5.0, 42.0]"
        end

        @testset "formats non-integer floats" begin
            result = Concore._format_wire([0.0, 3.14])
            @test occursin("3.14", result)
        end

        @testset "handles negative values" begin
            result = Concore._format_wire([0.0, -1.5])
            @test result == "[0.0, -1.5]"
        end

        @testset "single value" begin
            @test Concore._format_wire([7.0]) == "[7.0]"
        end

        @testset "multiple values" begin
            result = Concore._format_wire([1.0, 2.0, 3.0])
            @test result == "[1.0, 2.0, 3.0]"
        end

    end

    # =========================================================================
    # _cap_s
    # =========================================================================

    @testset "_cap_s" begin

        @testset "appends strings" begin
            @test Concore._cap_s("hello", " world") == "hello world"
        end

        @testset "empty strings" begin
            @test Concore._cap_s("", "") == ""
            @test Concore._cap_s("", "data") == "data"
            @test Concore._cap_s("data", "") == "data"
        end

        @testset "truncates when exceeding max length" begin
            long_str = repeat("x", 70000)
            result = Concore._cap_s("", long_str)
            @test length(result) <= 65536
        end

    end

end
