#=
test_full_pipeline.jl -- End-to-end pipeline integration test

Simulates the full mkconcore workflow:
  1. Parse demo/sample.graphml
  2. Create workspace directory structure
  3. Set up symlinks, port configs, initial data
  4. Launch controller.jl and pm.jl as separate processes
  5. Wait for completion
  6. Verify final data files contain expected values
  7. Report PASS/FAIL

Usage:
    julia test/integration/test_full_pipeline.jl
=#

const TEST_DIR = @__DIR__
const REPO_ROOT = dirname(dirname(TEST_DIR))
push!(LOAD_PATH, REPO_ROOT)
using Concore: safe_parse_list

# ═════════════════════════════════════════════════════════════════════════════
# Minimal GraphML parser (just enough for sample.graphml)
# ═════════════════════════════════════════════════════════════════════════════

struct GraphNode
    id::String
    cmd::String
end

struct GraphEdge
    id::String
    source::String
    target::String
    init::String
end

"""Parse a simple GraphML file into nodes and edges."""
function parse_graphml(path::String)
    content = read(path, String)

    nodes = GraphNode[]
    edges = GraphEdge[]

    # Parse nodes: <node id="..."><data key="cmd">...</data></node>
    for m in eachmatch(r"<node\s+id=\"([^\"]+)\"[^>]*>(.*?)</node>"s, content)
        node_id = m.captures[1]
        body = m.captures[2]
        cmd_m = match(r"<data\s+key=\"cmd\">(.*?)</data>", body)
        cmd = cmd_m !== nothing ? cmd_m.captures[1] : ""
        push!(nodes, GraphNode(node_id, cmd))
    end

    # Parse edges: <edge id="..." source="..." target="..."><data key="init">...</data></edge>
    for m in eachmatch(r"<edge\s+id=\"([^\"]+)\"\s+source=\"([^\"]+)\"\s+target=\"([^\"]+)\"[^>]*>(.*?)</edge>"s, content)
        edge_id = m.captures[1]
        source = m.captures[2]
        target = m.captures[3]
        body = m.captures[4]
        init_m = match(r"<data\s+key=\"init\">(.*?)</data>", body)
        init = init_m !== nothing ? init_m.captures[1] : "[0.0, 0.0]"
        push!(edges, GraphEdge(edge_id, source, target, init))
    end

    return nodes, edges
end

# ═════════════════════════════════════════════════════════════════════════════
# Test execution
# ═════════════════════════════════════════════════════════════════════════════

function run_pipeline_test()
    passed = 0
    failed = 0
    total = 0

    function check(name, cond)
        total += 1
        if cond
            passed += 1
            println("  PASS: $name")
        else
            failed += 1
            println("  FAIL: $name")
        end
    end

    println("=" ^ 60)
    println("Full Pipeline Integration Test")
    println("=" ^ 60)

    # ── Step 1: Parse GraphML ────────────────────────────────────────────
    println("\n[1/7] Parsing demo/sample.graphml...")
    graphml_path = joinpath(REPO_ROOT, "demo", "sample.graphml")
    nodes, edges = parse_graphml(graphml_path)

    check("found 2 nodes", length(nodes) == 2)
    check("found 2 edges", length(edges) == 2)
    check("node CZ exists", any(n -> n.id == "CZ", nodes))
    check("node PZ exists", any(n -> n.id == "PZ", nodes))
    check("edge CU exists", any(e -> e.id == "CU", edges))
    check("edge PYM exists", any(e -> e.id == "PYM", edges))

    cu_edge = first(e for e in edges if e.id == "CU")
    pym_edge = first(e for e in edges if e.id == "PYM")
    check("CU: CZ -> PZ", cu_edge.source == "CZ" && cu_edge.target == "PZ")
    check("PYM: PZ -> CZ", pym_edge.source == "PZ" && pym_edge.target == "CZ")

    # ── Step 2: Create workspace ─────────────────────────────────────────
    println("\n[2/7] Creating workspace directory structure...")
    work_dir = mktempdir(; cleanup=true)

    # Create edge directories
    for edge in edges
        mkpath(joinpath(work_dir, edge.id))
    end

    # Create node directories
    for node in nodes
        mkpath(joinpath(work_dir, node.id))
    end

    check("workspace created", isdir(work_dir))
    check("CU dir exists", isdir(joinpath(work_dir, "CU")))
    check("PYM dir exists", isdir(joinpath(work_dir, "PYM")))
    check("CZ dir exists", isdir(joinpath(work_dir, "CZ")))
    check("PZ dir exists", isdir(joinpath(work_dir, "PZ")))

    # ── Step 3: Set up symlinks and port configs ─────────────────────────
    println("\n[3/7] Setting up symlinks and config files...")

    # Build port mappings from edge topology
    # For each node: input edges are edges where node is the target,
    #                output edges are edges where node is the source.
    for node in nodes
        node_dir = joinpath(work_dir, node.id)

        in_edges = filter(e -> e.target == node.id, edges)
        out_edges = filter(e -> e.source == node.id, edges)

        # Create iport config
        iport_entries = join(["'$(e.id)': $(i)" for (i, e) in enumerate(in_edges)], ", ")
        write(joinpath(node_dir, "concore.iport"), "{$iport_entries}")

        # Create oport config
        oport_entries = join(["'$(e.id)': $(i)" for (i, e) in enumerate(out_edges)], ", ")
        write(joinpath(node_dir, "concore.oport"), "{$oport_entries}")

        # Create symlinks for input ports
        for (i, e) in enumerate(in_edges)
            symlink(joinpath(work_dir, e.id), joinpath(node_dir, "in$i"))
        end

        # Create symlinks for output ports
        for (i, e) in enumerate(out_edges)
            symlink(joinpath(work_dir, e.id), joinpath(node_dir, "out$i"))
        end
    end

    check("CZ/in1 symlink exists", islink(joinpath(work_dir, "CZ", "in1")))
    check("CZ/out1 symlink exists", islink(joinpath(work_dir, "CZ", "out1")))
    check("PZ/in1 symlink exists", islink(joinpath(work_dir, "PZ", "in1")))
    check("PZ/out1 symlink exists", islink(joinpath(work_dir, "PZ", "out1")))
    check("CZ iport written", isfile(joinpath(work_dir, "CZ", "concore.iport")))
    check("PZ oport written", isfile(joinpath(work_dir, "PZ", "concore.oport")))

    # ── Step 4: Write initial data ───────────────────────────────────────
    println("\n[4/7] Writing initial data files...")

    maxtime = 15

    for edge in edges
        edge_dir = joinpath(work_dir, edge.id)
        # Write initial data using the edge name (lowercase for file convention)
        # The actual file name depends on the data label; for this demo:
        # CU carries "u", PYM carries "ym"
        if edge.id == "CU"
            write(joinpath(edge_dir, "u"), edge.init)
        elseif edge.id == "PYM"
            write(joinpath(edge_dir, "ym"), edge.init)
        end
    end

    # Write maxtime into the in1/ directory for each node
    for node in nodes
        in1_dir = joinpath(work_dir, node.id, "in1")
        if isdir(in1_dir) || islink(in1_dir)
            write(joinpath(in1_dir, "concore.maxtime"), string(maxtime))
        end
    end

    check("CU/u initialized", isfile(joinpath(work_dir, "CU", "u")))
    check("PYM/ym initialized", isfile(joinpath(work_dir, "PYM", "ym")))
    check("CZ maxtime written", isfile(joinpath(work_dir, "CZ", "in1", "concore.maxtime")))
    check("PZ maxtime written", isfile(joinpath(work_dir, "PZ", "in1", "concore.maxtime")))

    # ── Step 5: Launch controller and plant model ────────────────────────
    println("\n[5/7] Launching Julia processes...")

    controller_script = joinpath(REPO_ROOT, "demo", "controller.jl")
    pm_script = joinpath(REPO_ROOT, "demo", "pm.jl")
    julia_cmd = Base.julia_cmd()

    cz_dir = joinpath(work_dir, "CZ")
    pz_dir = joinpath(work_dir, "PZ")

    controller_proc = run(
        pipeline(
            Cmd(`$julia_cmd --project=$REPO_ROOT $controller_script`; dir=cz_dir),
            stdout=joinpath(cz_dir, "concoreout.txt"),
            stderr=joinpath(cz_dir, "concoreerr.txt"),
        );
        wait=false,
    )

    pm_proc = run(
        pipeline(
            Cmd(`$julia_cmd --project=$REPO_ROOT $pm_script`; dir=pz_dir),
            stdout=joinpath(pz_dir, "concoreout.txt"),
            stderr=joinpath(pz_dir, "concoreerr.txt"),
        );
        wait=false,
    )

    check("controller started", process_running(controller_proc))
    check("plant model started", process_running(pm_proc))

    # ── Step 6: Wait for completion ──────────────────────────────────────
    println("\n[6/7] Waiting for processes to complete...")

    timeout_sec = 120
    timer = Timer(timeout_sec) do t
        if process_running(controller_proc)
            println("  TIMEOUT: killing controller")
            kill(controller_proc)
        end
        if process_running(pm_proc)
            println("  TIMEOUT: killing plant model")
            kill(pm_proc)
        end
    end

    wait(controller_proc)
    wait(pm_proc)
    close(timer)

    c_exit = controller_proc.exitcode
    p_exit = pm_proc.exitcode

    check("controller exited 0", c_exit == 0)
    check("plant model exited 0", p_exit == 0)

    # ── Step 7: Verify final data ────────────────────────────────────────
    println("\n[7/7] Verifying final data files...")

    # Read final values
    final_u = try
        strip(read(joinpath(work_dir, "CU", "u"), String))
    catch
        ""
    end

    final_ym = try
        strip(read(joinpath(work_dir, "PYM", "ym"), String))
    catch
        ""
    end

    println("  CU/u  = $final_u")
    println("  PYM/ym = $final_ym")

    check("CU/u is not empty", !isempty(final_u))
    check("PYM/ym is not empty", !isempty(final_ym))
    check("CU/u has valid wire format", startswith(final_u, "[") && endswith(final_u, "]"))
    check("PYM/ym has valid wire format", startswith(final_ym, "[") && endswith(final_ym, "]"))

    # Parse and verify simtime advanced
    if !isempty(final_u) && startswith(final_u, "[")
        u_vals = safe_parse_list(final_u)
        ym_vals = safe_parse_list(final_ym)
        check("simtime advanced (u)", u_vals[1] > 0.0)
        check("simtime advanced (ym)", ym_vals[1] > 0.0)
        check("final simtime >= maxtime - 1", u_vals[1] >= maxtime - 1)
        # The bang-bang controller should drive ym toward ysp=3.0
        # After many iterations, ym should be in a reasonable range (not 0)
        check("ym data is non-zero", abs(ym_vals[2]) > 0.0)
    end

    # ── Summary ──────────────────────────────────────────────────────────
    println("\n" * "=" ^ 60)
    println("Results: $passed passed, $failed failed, $total total")
    if failed == 0
        println("PASS: Full pipeline integration test succeeded.")
    else
        println("FAIL: $failed test(s) failed.")
    end
    println("=" ^ 60)

    return failed == 0
end

# Run and exit with appropriate code
success = run_pipeline_test()
exit(success ? 0 : 1)
