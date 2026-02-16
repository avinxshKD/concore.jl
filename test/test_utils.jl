using Concore.ConcoreUtils
using EzXML

@testset "ConcoreUtils" begin

    # =========================================================================
    # PIDController construction
    # =========================================================================

    @testset "PIDController construction" begin

        @testset "full constructor (6 args with output limits)" begin
            ctrl = PIDController("ctrl", 1.0, 0.5, 0.1, -10.0, 10.0)
            @test ctrl.id == "ctrl"
            @test ctrl.kp == 1.0
            @test ctrl.ki == 0.5
            @test ctrl.kd == 0.1
            @test ctrl.output_min == -10.0
            @test ctrl.output_max == 10.0
        end

        @testset "convenience constructor (4 args, no limits)" begin
            ctrl = PIDController("ctrl", 2.0, 0.5, 0.1)
            @test ctrl.id == "ctrl"
            @test ctrl.kp == 2.0
            @test ctrl.ki == 0.5
            @test ctrl.kd == 0.1
            @test ctrl.output_min == -Inf
            @test ctrl.output_max == Inf
        end

        @testset "P-only controller" begin
            ctrl = PIDController("p_only", 3.0, 0.0, 0.0)
            @test ctrl.kp == 3.0
            @test ctrl.ki == 0.0
            @test ctrl.kd == 0.0
        end

        @testset "PI controller" begin
            ctrl = PIDController("pi", 1.0, 0.5, 0.0)
            @test ctrl.ki == 0.5
            @test ctrl.kd == 0.0
        end

        @testset "PD controller" begin
            ctrl = PIDController("pd", 1.0, 0.0, 0.3)
            @test ctrl.ki == 0.0
            @test ctrl.kd == 0.3
        end

        @testset "PIDController is immutable (struct)" begin
            ctrl = PIDController("ctrl", 1.0, 0.5, 0.1)
            @test !ismutable(ctrl)
        end

        @testset "PIDNode is an alias for PIDController" begin
            @test PIDNode === PIDController
            node = PIDNode("alias", 1.0, 0.0, 0.0)
            @test node isa PIDController
        end

        @testset "constructor accepts Real arguments" begin
            ctrl = PIDController("int_args", 2, 1, 0)
            @test ctrl.kp === 2.0
            @test ctrl.ki === 1.0
            @test ctrl.kd === 0.0
        end

    end

    # =========================================================================
    # PIDState construction and mutability
    # =========================================================================

    @testset "PIDState construction" begin

        @testset "default constructor zeros fields" begin
            state = PIDState()
            @test state.integral == 0.0
            @test state.prev_error == 0.0
        end

        @testset "explicit constructor" begin
            state = PIDState(5.0, 3.0)
            @test state.integral == 5.0
            @test state.prev_error == 3.0
        end

        @testset "PIDState is mutable" begin
            state = PIDState()
            @test ismutable(state)
            state.integral = 42.0
            @test state.integral == 42.0
            state.prev_error = 7.0
            @test state.prev_error == 7.0
        end

    end

    # =========================================================================
    # reset!
    # =========================================================================

    @testset "reset!" begin

        @testset "clears integral and prev_error on PIDState" begin
            state = PIDState(10.0, 5.0)
            reset!(state)
            @test state.integral == 0.0
            @test state.prev_error == 0.0
        end

        @testset "returns the state object" begin
            state = PIDState(10.0, 5.0)
            result = reset!(state)
            @test result === state
        end

        @testset "reset already clean state" begin
            state = PIDState()
            reset!(state)
            @test state.integral == 0.0
            @test state.prev_error == 0.0
        end

        @testset "reset! with String ID clears _state_cache" begin
            ctrl = PIDController("cache_test", 1.0, 1.0, 0.0)
            # Execute using convenience form to populate _state_cache
            execute_step(ctrl, 5.0)
            execute_step(ctrl, 5.0)
            # Reset cached state by ID
            reset!("cache_test")
            # After reset, next call should start fresh
            out = execute_step(ctrl, 1.0)
            # P=1.0*1.0=1.0, I=1.0*1.0=1.0, D=1.0*(1.0-0.0)/1.0=1.0 => 3.0
            # Wait: kd=0.0, so D=0
            # P=1.0, I=1.0 => 2.0
            @test out ≈ 2.0
        end

        @testset "reset! with nonexistent ID is a no-op" begin
            # Should not throw
            reset!("nonexistent_id_xyz")
            @test true  # if we get here, it didn't throw
        end

    end

    # =========================================================================
    # execute_step (4-arg: ctrl, state, error, dt)
    # =========================================================================

    @testset "execute_step (ctrl, state, error, dt)" begin

        @testset "proportional only" begin
            ctrl = PIDController("p", 2.0, 0.0, 0.0)
            state = PIDState()
            output = execute_step(ctrl, state, 1.0)
            @test output ≈ 2.0
        end

        @testset "proportional with larger error" begin
            ctrl = PIDController("p", 3.0, 0.0, 0.0)
            state = PIDState()
            output = execute_step(ctrl, state, 5.0)
            @test output ≈ 15.0
        end

        @testset "integral accumulation" begin
            ctrl = PIDController("i", 0.0, 1.0, 0.0)
            state = PIDState()

            out1 = execute_step(ctrl, state, 1.0)
            @test out1 ≈ 1.0  # integral = 1.0

            out2 = execute_step(ctrl, state, 1.0)
            @test out2 ≈ 2.0  # integral = 2.0

            out3 = execute_step(ctrl, state, 1.0)
            @test out3 ≈ 3.0  # integral = 3.0
        end

        @testset "integral with custom dt" begin
            ctrl = PIDController("i", 0.0, 1.0, 0.0)
            state = PIDState()
            output = execute_step(ctrl, state, 2.0, 0.5)
            @test output ≈ 1.0  # integral = 2.0 * 0.5 = 1.0, ki * 1.0 = 1.0
        end

        @testset "derivative term" begin
            ctrl = PIDController("d", 0.0, 0.0, 1.0)
            state = PIDState()

            out1 = execute_step(ctrl, state, 2.0)
            @test out1 ≈ 2.0  # d = 1.0 * (2.0 - 0.0) / 1.0

            out2 = execute_step(ctrl, state, 3.0)
            @test out2 ≈ 1.0  # d = 1.0 * (3.0 - 2.0) / 1.0
        end

        @testset "derivative with custom dt" begin
            ctrl = PIDController("d", 0.0, 0.0, 1.0)
            state = PIDState()
            output = execute_step(ctrl, state, 4.0, 2.0)
            @test output ≈ 2.0  # d = 1.0 * (4.0 - 0.0) / 2.0
        end

        @testset "full PID combination" begin
            ctrl = PIDController("pid", 1.0, 0.5, 0.1)
            state = PIDState()

            output = execute_step(ctrl, state, 10.0, 1.0)
            # P = 1.0 * 10.0 = 10.0
            # I = 0.5 * 10.0 = 5.0 (integral = 10.0)
            # D = 0.1 * (10.0 - 0.0) / 1.0 = 1.0
            @test output ≈ 16.0
        end

        @testset "zero error" begin
            ctrl = PIDController("z", 1.0, 0.5, 0.1)
            state = PIDState()
            output = execute_step(ctrl, state, 0.0)
            @test output ≈ 0.0
        end

        @testset "negative error" begin
            ctrl = PIDController("n", 2.0, 0.0, 0.0)
            state = PIDState()
            output = execute_step(ctrl, state, -3.0)
            @test output ≈ -6.0
        end

        @testset "state is modified in-place" begin
            ctrl = PIDController("s", 1.0, 1.0, 1.0)
            state = PIDState()

            execute_step(ctrl, state, 1.0)
            @test state.integral ≈ 1.0
            @test state.prev_error ≈ 1.0

            execute_step(ctrl, state, 2.0)
            @test state.integral ≈ 3.0
            @test state.prev_error ≈ 2.0
        end

        @testset "reset clears accumulated state" begin
            ctrl = PIDController("r", 1.0, 1.0, 0.0)
            state = PIDState()
            execute_step(ctrl, state, 5.0)
            execute_step(ctrl, state, 5.0)
            @test state.integral ≈ 10.0

            reset!(state)
            @test state.integral == 0.0
            @test state.prev_error == 0.0

            output = execute_step(ctrl, state, 1.0)
            # P=1.0, I=1.0 (fresh integral=1.0), D=0.0 => 2.0
            @test output ≈ 2.0
        end

        @testset "default dt is 1.0" begin
            ctrl = PIDController("dt", 0.0, 1.0, 0.0)
            state1 = PIDState()
            state2 = PIDState()

            out1 = execute_step(ctrl, state1, 5.0)
            out2 = execute_step(ctrl, state2, 5.0, 1.0)

            @test out1 ≈ out2
        end

    end

    # =========================================================================
    # execute_step — anti-windup clamping
    # =========================================================================

    @testset "anti-windup clamping" begin

        @testset "output clamped to output_max" begin
            ctrl = PIDController("clamp", 10.0, 0.0, 0.0, -5.0, 5.0)
            state = PIDState()
            output = execute_step(ctrl, state, 10.0)
            @test output ≈ 5.0
        end

        @testset "output clamped to output_min" begin
            ctrl = PIDController("clamp", 10.0, 0.0, 0.0, -5.0, 5.0)
            state = PIDState()
            output = execute_step(ctrl, state, -10.0)
            @test output ≈ -5.0
        end

        @testset "integral frozen when output saturated" begin
            ctrl = PIDController("windup", 0.0, 1.0, 0.0, -Inf, 5.0)
            state = PIDState()
            # First step: integral = 10.0, output = 10.0 > 5.0 => clamped, integral frozen at 0.0
            out1 = execute_step(ctrl, state, 10.0)
            @test out1 ≈ 5.0
            @test state.integral ≈ 0.0  # frozen, not updated to 10.0

            # Second step with small error: integral = 0.0 + 1.0 = 1.0, output = 1.0 <= 5.0 => accepted
            out2 = execute_step(ctrl, state, 1.0)
            @test out2 ≈ 1.0
            @test state.integral ≈ 1.0
        end

        @testset "no clamping when within limits" begin
            ctrl = PIDController("nocl", 1.0, 0.0, 0.0, -100.0, 100.0)
            state = PIDState()
            output = execute_step(ctrl, state, 5.0)
            @test output ≈ 5.0
        end

        @testset "no limits (default Inf) means no clamping" begin
            ctrl = PIDController("inf", 1.0, 0.0, 0.0)
            state = PIDState()
            output = execute_step(ctrl, state, 1e10)
            @test output ≈ 1e10
        end

    end

    # =========================================================================
    # execute_step (convenience 2-arg: ctrl, error — uses _state_cache)
    # =========================================================================

    @testset "execute_step convenience (ctrl, error)" begin

        @testset "basic proportional" begin
            ctrl = PIDController("conv_p", 2.0, 0.0, 0.0)
            reset!("conv_p")
            output = execute_step(ctrl, 1.0)
            @test output ≈ 2.0
        end

        @testset "state persists across calls via cache" begin
            ctrl = PIDController("conv_persist", 0.0, 1.0, 0.0)
            reset!("conv_persist")

            out1 = execute_step(ctrl, 1.0)
            @test out1 ≈ 1.0

            out2 = execute_step(ctrl, 1.0)
            @test out2 ≈ 2.0
        end

        @testset "different IDs have independent state" begin
            ctrl_a = PIDController("indep_a", 0.0, 1.0, 0.0)
            ctrl_b = PIDController("indep_b", 0.0, 1.0, 0.0)
            reset!("indep_a")
            reset!("indep_b")

            execute_step(ctrl_a, 5.0)
            execute_step(ctrl_a, 5.0)  # integral for a = 10

            out_b = execute_step(ctrl_b, 3.0)  # integral for b = 3
            @test out_b ≈ 3.0
        end

        @testset "convenience form with custom dt" begin
            ctrl = PIDController("conv_dt", 0.0, 1.0, 0.0)
            reset!("conv_dt")
            output = execute_step(ctrl, 4.0, 0.5)
            @test output ≈ 2.0  # integral = 4.0 * 0.5 = 2.0
        end

    end

    # =========================================================================
    # PIDController show method
    # =========================================================================

    @testset "show methods" begin

        @testset "PIDController show without limits" begin
            ctrl = PIDController("test", 2.0, 0.5, 0.1)
            s = sprint(show, ctrl)
            @test occursin("PIDController", s)
            @test occursin("test", s)
            @test occursin("kp=2.0", s)
        end

        @testset "PIDController show with limits" begin
            ctrl = PIDController("test", 2.0, 0.5, 0.1, -10.0, 10.0)
            s = sprint(show, ctrl)
            @test occursin("limits=", s)
            @test occursin("-10.0", s)
            @test occursin("10.0", s)
        end

        @testset "PIDState show" begin
            state = PIDState(1.5, 2.5)
            s = sprint(show, state)
            @test occursin("PIDState", s)
            @test occursin("integral=", s)
            @test occursin("prev_error=", s)
        end

    end

    # =========================================================================
    # load_graph (GraphML parsing)
    # =========================================================================

    @testset "load_graph" begin

        @testset "loads single node from GraphML" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="n1">
      <data key="kp">2.0</data>
      <data key="ki">0.5</data>
      <data key="kd">0.1</data>
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                @test length(nodes) == 1
                ctrl, state = nodes[1]
                @test ctrl.id == "n1"
                @test ctrl.kp == 2.0
                @test ctrl.ki == 0.5
                @test ctrl.kd == 0.1
                @test state.integral == 0.0
                @test state.prev_error == 0.0
            end
        end

        @testset "loads multiple nodes" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="controller">
      <data key="kp">2.0</data>
      <data key="ki">0.5</data>
      <data key="kd">0.1</data>
    </node>
    <node id="plant">
      <data key="kp">1.0</data>
      <data key="ki">0.0</data>
      <data key="kd">0.0</data>
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                @test length(nodes) == 2
                @test nodes[1][1].id == "controller"
                @test nodes[2][1].id == "plant"
            end
        end

        @testset "default gains when data missing" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="minimal">
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                @test length(nodes) == 1
                ctrl, _ = nodes[1]
                @test ctrl.kp == 1.0  # default
                @test ctrl.ki == 0.0  # default
                @test ctrl.kd == 0.0  # default
            end
        end

        @testset "partial gains (only kp specified)" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="p_only">
      <data key="kp">5.0</data>
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                ctrl, _ = nodes[1]
                @test ctrl.kp == 5.0
                @test ctrl.ki == 0.0
                @test ctrl.kd == 0.0
            end
        end

        @testset "empty graph returns empty vector" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
  </graph>
</graphml>""")
                nodes = load_graph(path)
                @test isempty(nodes)
                @test nodes isa Vector{Tuple{PIDController, PIDState}}
            end
        end

        @testset "missing file throws" begin
            @test_throws Exception load_graph("/nonexistent/test.graphml")
        end

        @testset "returns Vector{Tuple{PIDController, PIDState}}" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="n1">
      <data key="kp">1.0</data>
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                @test nodes isa Vector{Tuple{PIDController, PIDState}}
            end
        end

        @testset "edges are ignored" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="n1">
      <data key="kp">1.0</data>
    </node>
    <node id="n2">
      <data key="kp">2.0</data>
    </node>
    <edge id="e1" source="n1" target="n2"/>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                @test length(nodes) == 2
            end
        end

        @testset "each node gets fresh PIDState" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="a">
      <data key="kp">1.0</data>
    </node>
    <node id="b">
      <data key="kp">2.0</data>
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                _, state_a = nodes[1]
                _, state_b = nodes[2]
                # Modify one state, other should be unaffected
                state_a.integral = 99.0
                @test state_b.integral == 0.0
            end
        end

        @testset "controller from load_graph works with execute_step" begin
            mktempdir() do dir
                path = joinpath(dir, "test.graphml")
                write(path, """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="G" edgedefault="directed">
    <node id="pid1">
      <data key="kp">2.0</data>
      <data key="ki">0.5</data>
      <data key="kd">0.1</data>
    </node>
  </graph>
</graphml>""")
                nodes = load_graph(path)
                ctrl, state = nodes[1]
                output = execute_step(ctrl, state, 10.0, 1.0)
                # P = 2.0*10 = 20, I = 0.5*10 = 5, D = 0.1*(10-0)/1 = 1
                @test output ≈ 26.0
            end
        end

    end

end
