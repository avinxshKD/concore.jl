# Backends

Concore.jl supports multiple communication backends for inter-process communication. The backend determines how data is physically transferred between nodes.

## Backend Architecture

All backends implement the `AbstractBackend` interface:

```julia
abstract type AbstractBackend end
```

Each backend must support reading and writing string data to named channels (files, shared memory segments, etc.).

## File Backend (Default)

The `FileBackend` is the default and most portable backend. It communicates through plain text files on the filesystem.

```julia
backend = FileBackend(inpath="./in", outpath="./out")
```

### How it works

- **Write**: Data is written to `./out{port}/{name}` as a text file
- **Read**: Data is read from `./in{port}/{name}` by polling the file
- **Synchronization**: Polling with configurable delay (`Concore.delay`)

### Advantages

- Works on all platforms (Linux, macOS, Windows)
- No special dependencies
- Easy to debug (files are human-readable)
- Compatible with all concore language implementations

### Limitations

- Polling introduces latency (default 1 second delay)
- File I/O overhead for high-frequency communication
- Not suitable for real-time applications

### Configuration

```julia
Concore.delay = 0.1      # Reduce polling delay to 100ms
Concore.inpath = "./in"   # Input directory prefix
Concore.outpath = "./out" # Output directory prefix
```

## Docker Backend

The `DockerBackend` is used when nodes run inside Docker containers. The concore study runner (`concoredocker.py`) maps host directories into container mount points.

```julia
backend = DockerBackend()
```

### How it works

- **Convention**: Input directories are mounted at `/in{port}/` and output at `/out{port}/`
- **Detection**: `detect_environment()` checks for Docker-specific indicators (`.dockerenv`, cgroup)
- **Initialization**: `init_docker!()` reconfigures paths to use Docker mount points

### Directory mapping

| Host | Container |
|------|-----------|
| `./study/node1/out1/` | `/out1/` |
| `./study/node2/in1/` | `/in1/` |

### Usage

```julia
using Concore

if detect_environment() == :docker
    init_docker!()
end

# Rest of the node logic works identically
y = concore_read(1, "data", "[0.0, 0.0]")
```

### Building a Docker image

Use the included `Dockerfile`:

```bash
docker build -t concore-julia .
```

Run a node:

```bash
docker run -v ./in1:/in1 -v ./out1:/out1 concore-julia my_controller.jl
```

## Shared Memory Backend

The `SharedMemoryBackend` uses memory-mapped files for high-performance IPC between nodes on the same machine.

```julia
backend = SharedMemoryBackend(basepath="/dev/shm/concore")
```

### How it works

- **Implementation**: Uses Julia's `Mmap.mmap()` to create memory-mapped files
- **Location**: Files are created in `/dev/shm/` (Linux tmpfs) for true shared memory
- **Synchronization**: Atomic flag bytes in the mapped region

### Advantages

- Near-zero copy overhead
- Microsecond-level latency
- Suitable for high-frequency control loops

### Limitations

- Linux only (`/dev/shm/` is a Linux-specific tmpfs)
- Requires nodes to run on the same machine
- Not compatible with Docker networking (use Docker backend for containers)
- More complex error handling

### Performance characteristics

| Backend | Typical Latency | Throughput | Platform |
|---------|----------------|------------|----------|
| File | 10-1000 ms | Low | All |
| Docker | 10-1000 ms | Low | Docker |
| Shared Memory | 1-100 us | High | Linux |

## Selecting a Backend

The backend is selected based on the runtime environment:

1. **Automatic detection**: `concore_init!()` calls `detect_environment()` to determine if the node is running in Docker
2. **Manual selection**: Set `Concore.inpath` and `Concore.outpath` directly
3. **Shared memory**: Explicitly construct a `SharedMemoryBackend` when performance is critical

### Decision tree

```
Is the node running in Docker?
  Yes -> DockerBackend (auto-detected)
  No  -> Is low latency required?
    Yes -> SharedMemoryBackend (Linux only)
    No  -> FileBackend (default)
```

## Custom Backends

To implement a custom backend, define a new subtype of `AbstractBackend` and implement the required interface:

```julia
struct MyBackend <: AbstractBackend
    # configuration fields
end

# Implement read/write for your backend
function concore_read(backend::MyBackend, port::Int, name::String, init::String)
    # Your implementation
end

function concore_write(backend::MyBackend, port::Int, name::String, val::Vector{Float64}; delta::Int=0)
    # Your implementation
end
```
