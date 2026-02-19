@testset "Cross-Language Interoperability" begin

    function reset_interop_state!()
        Concore.simtime = 0.0
        Concore.delay = 0.0
        Concore.s = ""
        Concore.olds = ""
        Concore.retrycount = 0
    end

    # =========================================================================
    # Python str() output compatibility
    # =========================================================================

    @testset "parse Python str() output" begin

        @testset "Python str([1.0, 2.0, 3.0])" begin
            @test Concore.safe_parse_list("[1.0, 2.0, 3.0]") == [1.0, 2.0, 3.0]
        end

        @testset "Python str([0, 1, 2])" begin
            @test Concore.safe_parse_list("[0, 1, 2]") == [0.0, 1.0, 2.0]
        end

        @testset "Python str([-1.5, 0.001, 100.0])" begin
            @test Concore.safe_parse_list("[-1.5, 0.001, 100.0]") ≈ [-1.5, 0.001, 100.0]
        end

        @testset "Python str([0.0])" begin
            @test Concore.safe_parse_list("[0.0]") == [0.0]
        end

        @testset "Python str([True, False])" begin
            @test Concore.safe_parse_list("[True, False]") == [1.0, 0.0]
        end

        @testset "Python str([None])" begin
            @test Concore.safe_parse_list("[None]") == [0.0]
        end

    end

    # =========================================================================
    # Julia write format matches Python exactly
    # =========================================================================

    @testset "Julia write format" begin

        @testset "matches Python concore output for integer floats" begin
            mktempdir() do dir
                reset_interop_state!()
                old_outpath = Concore.outpath
                Concore.outpath = joinpath(dir, "out")
                Concore.simtime = 5.0

                Concore.concore_write(1, "test", [42.0, 3.0])

                content = read(joinpath(Concore.outpath * "1", "test"), String)
                # Python would produce: [5.0, 42.0, 3.0]
                @test content == "[5.0, 42.0, 3.0]"
                Concore.outpath = old_outpath
            end
        end

        @testset "matches Python format for mixed values" begin
            mktempdir() do dir
                reset_interop_state!()
                old_outpath = Concore.outpath
                Concore.outpath = joinpath(dir, "out")
                Concore.simtime = 0.0

                Concore.concore_write(1, "test", [3.14, 2.0, -1.5])

                content = read(joinpath(Concore.outpath * "1", "test"), String)
                # Must be parseable by Python concore
                @test startswith(content, "[")
                @test endswith(content, "]")
                # Verify it's also parseable by Julia
                parsed = Concore.safe_parse_list(content)
                @test parsed[1] == 0.0  # simtime
                @test parsed[2] ≈ 3.14
                @test parsed[3] == 2.0
                @test parsed[4] == -1.5
                Concore.outpath = old_outpath
            end
        end

    end

    # =========================================================================
    # Round-trip: Julia write → Python read → Python write → Julia read
    # =========================================================================

    @testset "round-trip compatibility" begin

        @testset "Julia-written data is parseable" begin
            mktempdir() do dir
                reset_interop_state!()
                old_outpath = Concore.outpath
                Concore.outpath = joinpath(dir, "io")
                Concore.simtime = 10.0

                Concore.concore_write(1, "signal", [1.5, -2.5, 0.0])

                content = read(joinpath(Concore.outpath * "1", "signal"), String)
                # Verify it can be parsed back (as Python would receive it)
                parsed = Concore.safe_parse_list(content)
                @test length(parsed) == 4  # simtime + 3 values
                @test parsed[1] == 10.0
                @test parsed[2] ≈ 1.5
                @test parsed[3] ≈ -2.5
                @test parsed[4] == 0.0
                Concore.outpath = old_outpath
            end
        end

        @testset "Python-format string is readable by Julia" begin
            mktempdir() do dir
                reset_interop_state!()
                old_inpath = Concore.inpath
                Concore.inpath = joinpath(dir, "in")
                mkpath(Concore.inpath * "1")

                # Simulate Python concore output
                python_output = "[5.0, 42.0, 3.14]"
                write(joinpath(Concore.inpath * "1", "signal"), python_output)

                result = Concore.concore_read(1, "signal", "[0.0, 0.0, 0.0]")
                @test result ≈ [42.0, 3.14]
                @test Concore.simtime == 5.0
                Concore.inpath = old_inpath
            end
        end

        @testset "Python-format with numpy annotations" begin
            mktempdir() do dir
                reset_interop_state!()
                old_inpath = Concore.inpath
                Concore.inpath = joinpath(dir, "in")
                mkpath(Concore.inpath * "1")

                # Simulate numpy-annotated output
                python_output = "[np.float64(5.0), np.float64(42.0), np.float64(3.14)]"
                write(joinpath(Concore.inpath * "1", "signal"), python_output)

                result = Concore.concore_read(1, "signal", "[0.0, 0.0, 0.0]")
                @test result ≈ [42.0, 3.14]
                @test Concore.simtime == 5.0
                Concore.inpath = old_inpath
            end
        end

    end

    # =========================================================================
    # Port config file compatibility
    # =========================================================================

    @testset "port config file format compatibility" begin

        @testset "Python-generated port file" begin
            mktempdir() do dir
                # Exactly what Python concore writes
                path = joinpath(dir, "concore.iport")
                write(path, "{'e1': 1, 'e2': 2}")
                result = Concore.parse_port_file(path)
                @test result == Dict("e1" => 1, "e2" => 2)
            end
        end

        @testset "Python single-port file" begin
            mktempdir() do dir
                path = joinpath(dir, "concore.oport")
                write(path, "{'e1': 1}")
                result = Concore.parse_port_file(path)
                @test result == Dict("e1" => 1)
            end
        end

        @testset "Python port file with spaces around colon" begin
            mktempdir() do dir
                path = joinpath(dir, "concore.port")
                write(path, "{'signal' : 3}")
                result = Concore.parse_port_file(path)
                @test result == Dict("signal" => 3)
            end
        end

    end

    # =========================================================================
    # Parameter file format compatibility
    # =========================================================================

    @testset "parameter file format compatibility" begin

        @testset "Python dict format params" begin
            mktempdir() do dir
                old_inpath = Concore.inpath
                Concore.inpath = joinpath(dir, "in")
                mkpath(Concore.inpath * "1")
                # Exactly what Python writes
                write(joinpath(Concore.inpath * "1", "concore.params"),
                      "{'gain': 2.5, 'mode': 'pid', 'steps': 100}")
                Concore.params = Dict{String,Any}()
                Concore.load_params()
                @test Concore.params["gain"] == 2.5
                @test Concore.params["mode"] == "pid"
                @test Concore.params["steps"] == 100.0
                Concore.inpath = old_inpath
            end
        end

        @testset "semicolon-separated format params" begin
            mktempdir() do dir
                old_inpath = Concore.inpath
                Concore.inpath = joinpath(dir, "in")
                mkpath(Concore.inpath * "1")
                write(joinpath(Concore.inpath * "1", "concore.params"),
                      "gain=2.5;mode=pid")
                Concore.params = Dict{String,Any}()
                Concore.load_params()
                @test Concore.params["gain"] == 2.5
                @test Concore.params["mode"] == "pid"
                Concore.inpath = old_inpath
            end
        end

    end

    # =========================================================================
    # Wire format edge cases from real Python concore usage
    # =========================================================================

    @testset "wire format edge cases" begin

        @testset "Python concore initial value string" begin
            # Common initial value strings used in Python concore examples
            result = Concore.safe_parse_list("[0.0, 0.0]")
            @test result == [0.0, 0.0]
        end

        @testset "Python concore with single data value" begin
            result = Concore.safe_parse_list("[10.0, 42.0]")
            @test result == [10.0, 42.0]
        end

        @testset "Python list with trailing space" begin
            result = Concore.safe_parse_list("[1.0, 2.0] ")
            @test result == [1.0, 2.0]
        end

        @testset "Python concore large arrays" begin
            # Python may produce large data arrays
            vals = join(["$i.0" for i in 0:50], ", ")
            result = Concore.safe_parse_list("[$vals]")
            @test length(result) == 51
            @test result[1] == 0.0
            @test result[end] == 50.0
        end

        @testset "very small float from Python" begin
            result = Concore.safe_parse_list("[0.0, 1e-12]")
            @test result[2] ≈ 1e-12
        end

        @testset "very large float from Python" begin
            result = Concore.safe_parse_list("[0.0, 1e12]")
            @test result[2] ≈ 1e12
        end

    end

    # =========================================================================
    # Module globals
    # =========================================================================

    @testset "module globals" begin

        @testset "simtime is mutable" begin
            old = Concore.simtime
            Concore.simtime = 999.0
            @test Concore.simtime == 999.0
            Concore.simtime = old
        end

        @testset "delay is mutable" begin
            old = Concore.delay
            Concore.delay = 0.5
            @test Concore.delay == 0.5
            Concore.delay = old
        end

        @testset "maxtime is mutable" begin
            old = Concore.maxtime
            Concore.maxtime = 500
            @test Concore.maxtime == 500
            Concore.maxtime = old
        end

        @testset "s is mutable" begin
            old = Concore.s
            Concore.s = "test"
            @test Concore.s == "test"
            Concore.s = old
        end

        @testset "olds is mutable" begin
            old = Concore.olds
            Concore.olds = "test"
            @test Concore.olds == "test"
            Concore.olds = old
        end

        @testset "inpath is mutable" begin
            old = Concore.inpath
            Concore.inpath = "/tmp/test_in"
            @test Concore.inpath == "/tmp/test_in"
            Concore.inpath = old
        end

        @testset "outpath is mutable" begin
            old = Concore.outpath
            Concore.outpath = "/tmp/test_out"
            @test Concore.outpath == "/tmp/test_out"
            Concore.outpath = old
        end

        @testset "iport is a Dict{String,Int}" begin
            @test Concore.iport isa Dict{String,Int}
        end

        @testset "oport is a Dict{String,Int}" begin
            @test Concore.oport isa Dict{String,Int}
        end

        @testset "params is a Dict{String,Any}" begin
            @test Concore.params isa Dict{String,Any}
        end

    end

end
