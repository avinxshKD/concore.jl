@testset "ZeroMQ Backend" begin

    # =========================================================================
    # ZeroMQBackend type
    # =========================================================================

    @testset "ZeroMQBackend type" begin

        @testset "is subtype of AbstractBackend" begin
            @test ZeroMQBackend <: AbstractBackend
        end

        @testset "can be instantiated" begin
            b = ZeroMQBackend()
            @test b isa AbstractBackend
            @test b isa ZeroMQBackend
        end

        @testset "can be used as ConCoreContext backend" begin
            ctx = ConCoreContext(backend = ZeroMQBackend())
            @test ctx.backend isa ZeroMQBackend
        end

    end

    # =========================================================================
    # Path helpers (sentinel values)
    # =========================================================================

    @testset "ZeroMQBackend path helpers" begin

        @testset "inpath returns zmq sentinel" begin
            @test Concore._backend_inpath(ZeroMQBackend()) == "zmq://in"
        end

        @testset "outpath returns zmq sentinel" begin
            @test Concore._backend_outpath(ZeroMQBackend()) == "zmq://out"
        end

        @testset "indir and outdir with ZeroMQBackend context" begin
            ctx = ConCoreContext(backend = ZeroMQBackend())
            @test Concore.indir(ctx, 1) == "zmq://in1"
            @test Concore.outdir(ctx, 1) == "zmq://out1"
            @test Concore.indir(ctx, 5) == "zmq://in5"
            @test Concore.outdir(ctx, 5) == "zmq://out5"
        end

    end

    # =========================================================================
    # Port registry (no ZMQ.jl needed)
    # =========================================================================

    @testset "port registry" begin

        @testset "registry starts empty or can be emptied" begin
            terminate_zmq()
            @test isempty(Concore._zmq_ports)
        end

        @testset "terminate_zmq is idempotent" begin
            terminate_zmq()
            terminate_zmq()
            @test isempty(Concore._zmq_ports)
        end

        @testset "terminate_zmq returns nothing" begin
            result = terminate_zmq()
            @test result === nothing
        end

    end

    # =========================================================================
    # Error handling for unregistered ports
    # =========================================================================

    @testset "unregistered port errors" begin

        @testset "zmq_read errors on unregistered port" begin
            terminate_zmq()
            if Concore.HAS_ZMQ
                @test_throws ErrorException zmq_read("nonexistent", "sig", "[0.0]")
            else
                # Without ZMQ, the _require_zmq check fires first
                @test_throws ErrorException zmq_read("nonexistent", "sig", "[0.0]")
            end
        end

        @testset "zmq_write errors on unregistered port" begin
            terminate_zmq()
            if Concore.HAS_ZMQ
                @test_throws ErrorException zmq_write("nonexistent", "sig", [1.0])
            else
                @test_throws ErrorException zmq_write("nonexistent", "sig", [1.0])
            end
        end

    end

    # =========================================================================
    # _require_zmq guard
    # =========================================================================

    @testset "_require_zmq" begin

        @testset "HAS_ZMQ is a Bool" begin
            @test Concore.HAS_ZMQ isa Bool
        end

        @testset "_require_zmq does not error when ZMQ available" begin
            if Concore.HAS_ZMQ
                @test Concore._require_zmq() === nothing
            end
        end

        @testset "_require_zmq errors when ZMQ unavailable" begin
            if !Concore.HAS_ZMQ
                @test_throws ErrorException Concore._require_zmq()
            end
        end

    end

    # =========================================================================
    # Wire format compatibility (uses shared _format_wire)
    # =========================================================================

    @testset "wire format for ZMQ payloads" begin

        @testset "format with simtime prefix" begin
            wire = Concore._format_wire([5.0, 42.0, 3.14])
            @test wire == "[5.0, 42.0, 3.14]"
        end

        @testset "format single value with simtime" begin
            wire = Concore._format_wire([0.0, 1.0])
            @test wire == "[0.0, 1.0]"
        end

        @testset "round-trip through parse" begin
            original = [10.0, 1.5, 2.5, 3.5]
            wire = Concore._format_wire(original)
            parsed = Concore.safe_parse_list(wire)
            @test parsed == original
        end

    end

    # =========================================================================
    # init_zmq_port validation (without actual ZMQ sockets)
    # =========================================================================

    @testset "init_zmq_port validation" begin

        @testset "rejects invalid port_type" begin
            if Concore.HAS_ZMQ
                @test_throws ErrorException init_zmq_port(
                    "bad", :foobar, "tcp://*:5555", :PUB
                )
            end
        end

        @testset "rejects unknown socket_type" begin
            if Concore.HAS_ZMQ
                @test_throws ErrorException Concore._zmq_socket_type(:XPUB)
            else
                @test_throws ErrorException Concore._zmq_socket_type(:XPUB)
            end
        end

    end

    # =========================================================================
    # Live ZMQ tests (only when ZMQ.jl is available)
    # =========================================================================

    if Concore.HAS_ZMQ
        @testset "live ZMQ round-trip (PUSH/PULL)" begin
            terminate_zmq()

            # Use an ephemeral inproc address to avoid port conflicts
            addr = "inproc://concore-test-$(rand(UInt32))"

            # PUSH binds (output), PULL connects (input)
            init_zmq_port("test_out", :output, addr, :PUSH)
            init_zmq_port("test_in",  :input,  addr, :PULL)

            @test haskey(Concore._zmq_ports, "test_out")
            @test haskey(Concore._zmq_ports, "test_in")

            # Give sockets time to connect
            sleep(0.1)

            # Save and restore simtime
            old_simtime = Concore.simtime
            Concore.simtime = 5.0

            # Write
            zmq_write("test_out", "sig", [42.0, 3.14]; delta=0)

            # Read
            result = zmq_read("test_in", "sig", "[0.0, 0.0, 0.0]")
            @test length(result) == 2
            @test result[1] == 42.0
            @test result[2] ≈ 3.14

            # Restore simtime
            Concore.simtime = old_simtime

            terminate_zmq()
            @test isempty(Concore._zmq_ports)
        end

        @testset "init_zmq_port replaces existing port" begin
            terminate_zmq()
            addr1 = "inproc://concore-replace-$(rand(UInt32))"
            addr2 = "inproc://concore-replace2-$(rand(UInt32))"

            init_zmq_port("repl", :output, addr1, :PUSH)
            @test Concore._zmq_ports["repl"].address == addr1

            init_zmq_port("repl", :output, addr2, :PUSH)
            @test Concore._zmq_ports["repl"].address == addr2
            @test length(Concore._zmq_ports) == 1

            terminate_zmq()
        end
    else
        @testset "ZMQ.jl not installed — socket operations gracefully error" begin
            @test_throws ErrorException init_zmq_port(
                "x", :output, "tcp://*:5555", :PUSH
            )
        end
    end

    # Final cleanup
    terminate_zmq()

end
