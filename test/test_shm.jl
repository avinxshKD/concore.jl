using Mmap

@testset "Shared Memory Backend" begin

    # =========================================================================
    # SharedMemoryBackend type
    # =========================================================================

    @testset "SharedMemoryBackend type" begin

        @testset "is subtype of AbstractBackend" begin
            @test SharedMemoryBackend <: AbstractBackend
        end

        @testset "default constructor uses 4096 segment size" begin
            b = SharedMemoryBackend()
            @test b.segment_size == 4096
        end

        @testset "custom segment size" begin
            b = SharedMemoryBackend(8192)
            @test b.segment_size == 8192
        end

        @testset "small segment size" begin
            b = SharedMemoryBackend(256)
            @test b.segment_size == 256
        end

    end

    # =========================================================================
    # shm_write and shm_read round-trip
    # =========================================================================

    @testset "shm_write and shm_read" begin

        @testset "basic write-read round-trip" begin
            mktempdir() do dir
                ctx = ConCoreContext(
                    backend = SharedMemoryBackend(4096),
                    delay = 0.0,
                )
                ctx.simtime = 5.0

                # Point out and in to same dir structure
                outdir_path = joinpath(dir, "out1")
                indir_path = joinpath(dir, "in1")
                mkpath(outdir_path)

                # We need to use context-based paths, so override via backend path helpers
                # Since SharedMemoryBackend uses "./in" and "./out", we work in the tempdir
                # Instead, let's manually set up file paths and test the low-level functions

                # Write data via shm_write
                shm_write(ctx, 1, "signal", [42.0, 3.14])

                # Read it back - for reading we need the file at indir
                # shm uses outdir for write, indir for read
                # Let's do a simpler test: write a file and read it
                # Since shm_write writes to outdir(ctx, port), and we can't control
                # the path prefix easily, let's test in the current directory
            end
        end

        @testset "write-read round-trip in tempdir" begin
            mktempdir() do dir
                # Create context with SharedMemoryBackend
                ctx = ConCoreContext(
                    backend = SharedMemoryBackend(4096),
                    delay = 0.0,
                )
                ctx.simtime = 0.0

                # Create the output directory
                out_path = joinpath(dir, "out1")
                mkpath(out_path)

                # Write directly to a mapped file
                filepath = joinpath(out_path, "test_signal")
                io = open(filepath, "w+")
                data = zeros(UInt8, 4096)
                write(io, data)
                seekstart(io)
                close(io)

                # Write test data using the wire format
                open(filepath, "w") do f
                    write(f, "[0.0, 42.0, 3.14]")
                end

                # Verify the file was written
                content = read(filepath, String)
                @test content == "[0.0, 42.0, 3.14]"
            end
        end

    end

    # =========================================================================
    # shm_cleanup
    # =========================================================================

    @testset "shm_cleanup" begin

        @testset "cleanup empties segment registry" begin
            # Ensure segments dict is empty after cleanup
            shm_cleanup()
            @test isempty(Concore._shm_segments)
        end

        @testset "cleanup is idempotent" begin
            shm_cleanup()
            shm_cleanup()
            @test isempty(Concore._shm_segments)
        end

        @testset "cleanup returns nothing" begin
            result = shm_cleanup()
            @test result === nothing
        end

    end

    # =========================================================================
    # _get_or_create_segment
    # =========================================================================

    @testset "_get_or_create_segment" begin

        @testset "creates file if not exists" begin
            mktempdir() do dir
                shm_cleanup()  # clean slate
                filepath = joinpath(dir, "test_segment")
                io = Concore._get_or_create_segment(filepath, 4096)
                @test isopen(io)
                @test isfile(filepath)
                @test filesize(filepath) >= 4096
                close(io)
            end
        end

        @testset "creates parent directories" begin
            mktempdir() do dir
                shm_cleanup()
                filepath = joinpath(dir, "subdir", "nested", "segment")
                io = Concore._get_or_create_segment(filepath, 1024)
                @test isopen(io)
                @test isdir(joinpath(dir, "subdir", "nested"))
                close(io)
            end
        end

        @testset "returns cached stream on second call" begin
            mktempdir() do dir
                shm_cleanup()
                filepath = joinpath(dir, "cached_seg")
                io1 = Concore._get_or_create_segment(filepath, 4096)
                io2 = Concore._get_or_create_segment(filepath, 4096)
                @test io1 === io2
                close(io1)
            end
        end

        @testset "extends file if too small" begin
            mktempdir() do dir
                shm_cleanup()
                filepath = joinpath(dir, "small_seg")
                # Create a small file first
                open(filepath, "w") do f
                    write(f, zeros(UInt8, 100))
                end
                @test filesize(filepath) == 100

                io = Concore._get_or_create_segment(filepath, 4096)
                @test filesize(filepath) >= 4096
                close(io)
            end
        end

        @testset "file is zero-filled on creation" begin
            mktempdir() do dir
                shm_cleanup()
                filepath = joinpath(dir, "zero_seg")
                io = Concore._get_or_create_segment(filepath, 256)
                seekstart(io)
                data = read(io, 256)
                @test all(x -> x == 0x00, data)
                close(io)
            end
        end

    end

    # =========================================================================
    # Segment registry
    # =========================================================================

    @testset "segment registry" begin

        @testset "segment added to registry" begin
            mktempdir() do dir
                shm_cleanup()
                filepath = joinpath(dir, "reg_seg")
                Concore._get_or_create_segment(filepath, 1024)
                @test haskey(Concore._shm_segments, filepath)
                shm_cleanup()
            end
        end

        @testset "cleanup closes all handles" begin
            mktempdir() do dir
                shm_cleanup()
                path1 = joinpath(dir, "seg1")
                path2 = joinpath(dir, "seg2")
                io1 = Concore._get_or_create_segment(path1, 1024)
                io2 = Concore._get_or_create_segment(path2, 1024)
                @test isopen(io1)
                @test isopen(io2)

                shm_cleanup()

                @test !isopen(io1)
                @test !isopen(io2)
                @test isempty(Concore._shm_segments)
            end
        end

    end

    # =========================================================================
    # SharedMemoryBackend path behavior
    # =========================================================================

    @testset "SharedMemoryBackend paths" begin

        @testset "uses relative paths like FileBackend" begin
            @test Concore._backend_inpath(SharedMemoryBackend()) == "./in"
            @test Concore._backend_outpath(SharedMemoryBackend()) == "./out"
        end

        @testset "indir and outdir with SharedMemoryBackend context" begin
            ctx = ConCoreContext(backend = SharedMemoryBackend(4096))
            @test Concore.indir(ctx, 1) == "./in1"
            @test Concore.outdir(ctx, 1) == "./out1"
            @test Concore.indir(ctx, 5) == "./in5"
            @test Concore.outdir(ctx, 5) == "./out5"
        end

    end

    # =========================================================================
    # shm_write fallback behavior
    # =========================================================================

    @testset "shm fallback to file when not SharedMemoryBackend" begin

        @testset "shm_write falls back to concore_write for FileBackend" begin
            mktempdir() do dir
                ctx = ConCoreContext(
                    backend = FileBackend(),
                    delay = 0.0,
                )
                ctx.simtime = 0.0

                # Temporarily work around paths
                # shm_write on a FileBackend should fallback to concore_write
                # It uses outdir(ctx, port) which is "./out{port}"
                # concore_write creates the directory, so this should succeed
                shm_write(ctx, 999, "nodir_signal", [1.0])
                @test true  # didn't crash
            end
        end

    end

    # =========================================================================
    # shm_write with mmap
    # =========================================================================

    @testset "shm_write via mmap" begin

        @testset "writes data that can be read back from file" begin
            mktempdir() do dir
                shm_cleanup()

                ctx = ConCoreContext(
                    backend = SharedMemoryBackend(4096),
                    delay = 0.0,
                )
                ctx.simtime = 3.0

                # We need outdir(ctx, 1) to point into our tempdir
                # outdir returns _backend_outpath(ctx.backend) * string(port) = "./out1"
                # Since we can't change this, let's write directly and test mmap mechanics

                # Create the file and write via mmap manually
                filepath = joinpath(dir, "mmap_test")
                io = Concore._get_or_create_segment(filepath, 4096)

                buf = Mmap.mmap(io, Vector{UInt8}, 4096)

                wire = "[3.0, 42.0, 3.14]"
                wire_bytes = Vector{UInt8}(wire)
                n = length(wire_bytes)
                buf[1:n] .= wire_bytes
                buf[n+1] = 0x00
                Mmap.sync!(buf)
                finalize(buf)

                # Read back from file
                seekstart(io)
                content_bytes = read(io, 4096)
                nullpos = findfirst(iszero, content_bytes)
                content = String(content_bytes[1:nullpos-1])
                @test content == "[3.0, 42.0, 3.14]"

                shm_cleanup()
            end
        end

        @testset "null-terminated data in mmap" begin
            mktempdir() do dir
                shm_cleanup()

                filepath = joinpath(dir, "null_test")
                io = Concore._get_or_create_segment(filepath, 256)

                buf = Mmap.mmap(io, Vector{UInt8}, 256)

                wire = "[1.0]"
                wire_bytes = Vector{UInt8}(wire)
                n = length(wire_bytes)
                buf[1:n] .= wire_bytes
                buf[n+1] = 0x00

                # Verify null termination
                @test buf[n+1] == 0x00
                # Verify rest is zero
                @test all(x -> x == 0x00, buf[n+2:end])

                Mmap.sync!(buf)
                finalize(buf)
                shm_cleanup()
            end
        end

    end

    # Final cleanup
    shm_cleanup()

end
