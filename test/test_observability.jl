@testset "Observability & Metrics" begin

    # =========================================================================
    # MetricsCollector creation
    # =========================================================================

    @testset "metrics_collector creation" begin
        mc = Concore.metrics_collector()
        @test mc isa Concore.MetricsCollector
        @test mc.read_count == 0
        @test mc.write_count == 0
        @test mc.errors_count == 0
        @test mc.total_bytes_read == 0
        @test mc.total_bytes_written == 0
        @test isempty(mc.read_latencies)
        @test isempty(mc.write_latencies)
        @test isempty(mc.sync_wait_times)
        @test isempty(mc.iteration_times)
        @test mc.enabled == true
        @test mc.start_time > 0.0
    end

    @testset "metrics_collector disabled" begin
        mc = Concore.metrics_collector(enabled = false)
        @test mc.enabled == false
        # Recording should be no-op when disabled
        Concore.record_read!(mc, 0.001, 100)
        @test mc.read_count == 0
        Concore.record_write!(mc, 0.002, 200)
        @test mc.write_count == 0
        Concore.record_error!(mc)
        @test mc.errors_count == 0
    end

    # =========================================================================
    # Recording operations
    # =========================================================================

    @testset "record_read!" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.005, 128)
        @test mc.read_count == 1
        @test length(mc.read_latencies) == 1
        @test mc.read_latencies[1] ≈ 0.005
        @test mc.total_bytes_read == 128

        Concore.record_read!(mc, 0.010, 256)
        @test mc.read_count == 2
        @test length(mc.read_latencies) == 2
        @test mc.total_bytes_read == 384
    end

    @testset "record_write!" begin
        mc = Concore.metrics_collector()
        Concore.record_write!(mc, 0.003, 64)
        @test mc.write_count == 1
        @test length(mc.write_latencies) == 1
        @test mc.write_latencies[1] ≈ 0.003
        @test mc.total_bytes_written == 64

        Concore.record_write!(mc, 0.007, 512)
        @test mc.write_count == 2
        @test mc.total_bytes_written == 576
    end

    @testset "record_sync_wait!" begin
        mc = Concore.metrics_collector()
        Concore.record_sync_wait!(mc, 0.050)
        @test length(mc.sync_wait_times) == 1
        @test mc.sync_wait_times[1] ≈ 0.050
    end

    @testset "record_iteration!" begin
        mc = Concore.metrics_collector()
        Concore.record_iteration!(mc, 0.100)
        @test length(mc.iteration_times) == 1
        @test mc.iteration_times[1] ≈ 0.100
    end

    @testset "record_error!" begin
        mc = Concore.metrics_collector()
        Concore.record_error!(mc)
        Concore.record_error!(mc)
        @test mc.errors_count == 2
    end

    # =========================================================================
    # Reset
    # =========================================================================

    @testset "reset_metrics!" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.001, 10)
        Concore.record_write!(mc, 0.002, 20)
        Concore.record_sync_wait!(mc, 0.050)
        Concore.record_iteration!(mc, 0.100)
        Concore.record_error!(mc)

        @test mc.read_count > 0  # sanity
        Concore.reset_metrics!(mc)

        @test mc.read_count == 0
        @test mc.write_count == 0
        @test mc.errors_count == 0
        @test mc.total_bytes_read == 0
        @test mc.total_bytes_written == 0
        @test isempty(mc.read_latencies)
        @test isempty(mc.write_latencies)
        @test isempty(mc.sync_wait_times)
        @test isempty(mc.iteration_times)
        @test mc.enabled == true  # enabled flag preserved
    end

    # =========================================================================
    # Summary computation
    # =========================================================================

    @testset "get_summary empty collector" begin
        mc = Concore.metrics_collector()
        s = Concore.get_summary(mc)
        @test s.read_count == 0
        @test s.write_count == 0
        @test s.error_rate == 0.0
        @test s.total_data_transferred == 0
        @test s.read_latency.count == 0
        @test s.read_latency.mean == 0.0
    end

    @testset "get_summary with data" begin
        mc = Concore.metrics_collector()

        # Simulate 10 reads with known latencies
        latencies = [0.001, 0.002, 0.003, 0.004, 0.005,
                     0.006, 0.007, 0.008, 0.009, 0.010]
        for lat in latencies
            Concore.record_read!(mc, lat, 100)
        end

        # 5 writes
        for i in 1:5
            Concore.record_write!(mc, 0.002 * i, 50)
        end

        # 1 error
        Concore.record_error!(mc)

        s = Concore.get_summary(mc)

        @test s.read_count == 10
        @test s.write_count == 5
        @test s.errors_count == 1
        @test s.total_bytes_read == 1000
        @test s.total_bytes_written == 250
        @test s.total_data_transferred == 1250

        # Check latency stats
        @test s.read_latency.count == 10
        @test s.read_latency.mean ≈ 0.0055 atol=1e-10
        @test s.read_latency.median ≈ 0.0055 atol=1e-10
        @test s.read_latency.min ≈ 0.001
        @test s.read_latency.max ≈ 0.010
        @test s.read_latency.p95 > s.read_latency.median
        @test s.read_latency.p99 >= s.read_latency.p95

        # Write latency
        @test s.write_latency.count == 5
        @test s.write_latency.min ≈ 0.002
        @test s.write_latency.max ≈ 0.010

        # Error rate = 1 / (10 + 5) = 0.0667
        @test s.error_rate ≈ 1.0 / 15.0 atol=1e-10

        # Throughput should be positive (uptime > 0)
        @test s.uptime > 0.0
        @test s.read_ops_per_sec > 0.0
        @test s.write_ops_per_sec > 0.0
    end

    @testset "get_summary single measurement" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.042, 256)
        s = Concore.get_summary(mc)

        @test s.read_count == 1
        @test s.read_latency.mean ≈ 0.042
        @test s.read_latency.median ≈ 0.042
        @test s.read_latency.p95 ≈ 0.042
        @test s.read_latency.p99 ≈ 0.042
        @test s.read_latency.min ≈ 0.042
        @test s.read_latency.max ≈ 0.042
    end

    # =========================================================================
    # Enable / Disable toggle
    # =========================================================================

    @testset "enable_metrics! and disable_metrics!" begin
        # Start clean
        Concore.disable_metrics!()
        Concore._global_collector = nothing

        Concore.enable_metrics!()
        @test Concore._metrics_enabled == true
        @test Concore._global_collector !== nothing

        gc = Concore.get_global_collector()
        @test gc isa Concore.MetricsCollector

        Concore.disable_metrics!()
        @test Concore._metrics_enabled == false
        # Collector should still exist
        @test Concore._global_collector !== nothing
    end

    @testset "enable_metrics! with custom collector" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.001, 10)

        Concore.enable_metrics!(collector = mc)
        @test Concore._global_collector === mc
        @test Concore.get_global_collector() === mc
        Concore.disable_metrics!()
    end

    @testset "module-global record functions respect enable flag" begin
        Concore.disable_metrics!()
        Concore._global_collector = nothing

        # Should be no-ops when disabled
        Concore.record_read!(0.001, 10)
        Concore.record_write!(0.001, 10)
        Concore.record_sync_wait!(0.01)
        Concore.record_iteration!(0.05)
        Concore.record_error!()

        # Enable and verify recording works
        Concore.enable_metrics!()
        gc = Concore.get_global_collector()::Concore.MetricsCollector
        @test gc.read_count == 0

        Concore.record_read!(0.005, 100)
        @test gc.read_count == 1

        Concore.record_write!(0.003, 50)
        @test gc.write_count == 1

        Concore.disable_metrics!()
    end

    # =========================================================================
    # print_metrics
    # =========================================================================

    @testset "print_metrics output" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.001, 100)
        Concore.record_write!(mc, 0.002, 200)

        buf = IOBuffer()
        Concore.print_metrics(buf, mc)
        output = String(take!(buf))

        @test occursin("ConCore Metrics Report", output)
        @test occursin("Reads:", output)
        @test occursin("Writes:", output)
        @test occursin("Errors:", output)
        @test occursin("Read Latency", output)
        @test occursin("Write Latency", output)
        @test occursin("ENABLED", output)
    end

    @testset "print_metrics empty collector" begin
        mc = Concore.metrics_collector()
        buf = IOBuffer()
        Concore.print_metrics(buf, mc)
        output = String(take!(buf))
        @test occursin("Reads:  0", output)
        @test occursin("Writes: 0", output)
    end

    @testset "print_metrics disabled collector" begin
        mc = Concore.metrics_collector(enabled = false)
        buf = IOBuffer()
        Concore.print_metrics(buf, mc)
        output = String(take!(buf))
        @test occursin("DISABLED", output)
    end

    @testset "print_metrics no global collector" begin
        old = Concore._global_collector
        Concore._global_collector = nothing
        buf = IOBuffer()
        Concore.print_metrics(buf)
        output = String(take!(buf))
        @test occursin("No metrics collector active", output)
        Concore._global_collector = old
    end

    # =========================================================================
    # export_metrics
    # =========================================================================

    @testset "export_metrics CSV" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.005, 128)
        Concore.record_read!(mc, 0.010, 256)
        Concore.record_write!(mc, 0.003, 64)

        mktempdir() do dir
            filepath = joinpath(dir, "metrics.csv")
            result = Concore.export_metrics(mc, filepath)
            @test result == filepath
            @test isfile(filepath)

            content = read(filepath, String)
            @test occursin("type,index,value_seconds,bytes", content)
            @test occursin("read_latency,1,", content)
            @test occursin("read_latency,2,", content)
            @test occursin("write_latency,1,", content)
            @test occursin("# read_count=2", content)
            @test occursin("# write_count=1", content)
        end
    end

    @testset "export_metrics text format" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.005, 128)

        mktempdir() do dir
            filepath = joinpath(dir, "metrics.txt")
            result = Concore.export_metrics(mc, filepath; format = :text)
            @test result == filepath
            @test isfile(filepath)

            content = read(filepath, String)
            @test occursin("ConCore Metrics Report", content)
            @test occursin("Reads:", content)
        end
    end

    @testset "export_metrics creates parent directories" begin
        mc = Concore.metrics_collector()

        mktempdir() do dir
            filepath = joinpath(dir, "sub", "dir", "metrics.csv")
            Concore.export_metrics(mc, filepath)
            @test isfile(filepath)
        end
    end

    # =========================================================================
    # show method
    # =========================================================================

    @testset "MetricsCollector show" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.001, 10)
        Concore.record_error!(mc)

        str = sprint(show, mc)
        @test occursin("MetricsCollector", str)
        @test occursin("reads=1", str)
        @test occursin("errors=1", str)
        @test occursin("enabled=true", str)
    end

    # =========================================================================
    # Edge cases
    # =========================================================================

    @testset "zero-latency recording" begin
        mc = Concore.metrics_collector()
        Concore.record_read!(mc, 0.0, 0)
        @test mc.read_count == 1
        @test mc.read_latencies[1] == 0.0
        @test mc.total_bytes_read == 0

        s = Concore.get_summary(mc)
        @test s.read_latency.mean == 0.0
    end

    @testset "large number of samples" begin
        mc = Concore.metrics_collector()
        for i in 1:1000
            Concore.record_read!(mc, Float64(i) / 10000.0, i)
        end

        @test mc.read_count == 1000
        @test length(mc.read_latencies) == 1000
        @test mc.total_bytes_read == sum(1:1000)

        s = Concore.get_summary(mc)
        @test s.read_latency.count == 1000
        @test s.read_latency.p99 > s.read_latency.p95
    end

    @testset "get_summary with no global collector" begin
        old = Concore._global_collector
        Concore._global_collector = nothing
        s = Concore.get_summary()
        @test s.read_count == 0
        @test s.write_count == 0
        @test s.uptime == 0.0
        Concore._global_collector = old
    end

    # =========================================================================
    # Format helpers (internal, but worth testing)
    # =========================================================================

    @testset "_fmt_time" begin
        @test occursin("ns", Concore._fmt_time(0.5e-9))
        @test occursin("μs", Concore._fmt_time(0.5e-4))
        @test occursin("ms", Concore._fmt_time(0.5e-1))
        @test occursin("s", Concore._fmt_time(1.5))
    end

    @testset "_fmt_bytes" begin
        @test Concore._fmt_bytes(500) == "500 B"
        @test occursin("KiB", Concore._fmt_bytes(2048))
        @test occursin("MiB", Concore._fmt_bytes(2 * 1024^2))
        @test occursin("GiB", Concore._fmt_bytes(2 * 1024^3))
    end

    # =========================================================================
    # Cleanup: restore module state
    # =========================================================================
    Concore.disable_metrics!()

end
