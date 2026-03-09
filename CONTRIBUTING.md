# Contributing to Concore.jl

Thank you for your interest in contributing to the Julia implementation of the concore protocol! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style](#code-style)
- [Architecture Overview](#architecture-overview)
- [Adding New Backends](#adding-new-backends)
- [Pull Request Process](#pull-request-process)
- [Julia Conventions](#julia-conventions)

## Development Setup

### Prerequisites

- **Julia 1.8+** (1.10+ recommended for development)
- **Git**
- **Python 3.8+** (optional, for interop tests)

### Clone and setup

```bash
git clone https://github.com/ControlCore-Project/concore.git
cd concore/concore-jl

# Activate and instantiate the project environment
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Verify the package loads
julia --project=. -e 'using Concore; println("OK")'
```

### Editor setup

For VS Code, install the [Julia extension](https://www.julia-vscode.org/) and set your project path to `concore-jl/`.

## Running Tests

### Full test suite

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Run specific test files

```bash
julia --project=. test/runtests.jl
```

### Run with verbose output

```bash
julia --project=. -e 'using Pkg; Pkg.test(; test_args=["--verbose"])'
```

### Test coverage

```bash
julia --project=. -e '
    using Pkg
    Pkg.test(; coverage=true)
'
# Process coverage files
julia -e '
    using Pkg; Pkg.add("CoverageTools")
    using CoverageTools
    coverage = process_folder("src")
    println("Coverage: ", get_summary(coverage))
'
```

## Code Style

Concore.jl uses [JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl) with the configuration in `.JuliaFormatter.toml`.

### Format code

```bash
# Install JuliaFormatter (one time)
julia -e 'using Pkg; Pkg.add("JuliaFormatter")'

# Format all source files
julia -e 'using JuliaFormatter; format("src/"); format("test/")'

# Check formatting without modifying files
julia -e 'using JuliaFormatter; format("src/", overwrite=false)'
```

### Key style rules

- **4-space indentation** (no tabs)
- **100-character line limit**
- **`for x in collection`** (not `for x = collection`)
- **Whitespace around type annotations**: `x :: Int` not `x::Int` in struct definitions
- **No trailing whitespace**
- **One blank line** between top-level definitions
- **Docstrings** on all exported functions

### Naming conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Functions | `snake_case` | `concore_read`, `safe_parse_list` |
| Mutating functions | `snake_case!` | `concore_init!`, `load_iport!` |
| Types | `PascalCase` | `ConCoreContext`, `FileBackend` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_BUFFER_SIZE` |
| Modules | `PascalCase` | `Concore`, `ConcoreUtils` |
| Local variables | `snake_case` | `retry_count`, `file_path` |

## Architecture Overview

```
src/
  Concore.jl          # Main module: exports, state, core I/O, init
  types.jl            # Type hierarchy: AbstractBackend, ConCoreContext
  parser.jl           # safe_parse_list, parse_port_file
  ConcoreUtils.jl     # Optional: PIDController, GraphML parsing
```

### Core design principles

1. **Zero-dependency core**: The core protocol (`concore_read`, `concore_write`, `initval`, `unchanged`) uses only Julia stdlib
2. **Wire format compatibility**: Output must be byte-identical to Python's concore output
3. **No `eval`/`Meta.parse`**: All parsing uses safe regex-based parsers (security requirement for file-based IPC)
4. **Module state**: Global state (`simtime`, `delay`, etc.) lives in module-level variables for compatibility with the Python API

### Data flow

```
Input File (in{port}/{name})
  -> concore_read()
    -> safe_parse_list()    # Parse wire format
    -> Extract simtime      # First element
    -> Return values        # Remaining elements

User computation (control law, plant model, etc.)

Output values
  -> concore_write()
    -> Format wire string   # [simtime+delta, val1, val2, ...]
    -> Write to file        # out{port}/{name}
```

## Adding New Backends

To add a new IPC backend:

### 1. Define the type

In `src/types.jl`:

```julia
"""
    RedisBackend <: AbstractBackend

Backend using Redis for inter-node communication.
"""
struct RedisBackend <: AbstractBackend
    host::String
    port::Int
    prefix::String
end
```

### 2. Implement the interface

Create `src/redis.jl`:

```julia
function backend_read(b::RedisBackend, port::Int, name::String)::String
    key = "$(b.prefix):in$(port):$(name)"
    # Read from Redis
    return redis_get(b.host, b.port, key)
end

function backend_write(b::RedisBackend, port::Int, name::String, data::String)
    key = "$(b.prefix):out$(port):$(name)"
    # Write to Redis
    redis_set(b.host, b.port, key, data)
end
```

### 3. Add tests

In `test/test_redis_backend.jl`:

```julia
@testset "RedisBackend" begin
    backend = RedisBackend("localhost", 6379, "concore_test")
    # Test read/write round-trip
    # Test error handling
    # Test concurrent access
end
```

### 4. Include in the module

In `src/Concore.jl`, add:

```julia
include("redis.jl")
```

### 5. Add optional dependency

If the backend requires an external package, add it as a weak dependency in `Project.toml`:

```toml
[weakdeps]
Redis = "..."

[extensions]
ConcoreRedisExt = "Redis"
```

## Pull Request Process

1. **Fork** the repository and create a feature branch from `main`
2. **Write tests** for any new functionality
3. **Format code** with JuliaFormatter before committing
4. **Run the full test suite** and ensure all tests pass
5. **Update documentation** if adding new public API
6. **Write a clear PR description** explaining what and why

### PR checklist

- [ ] Tests pass locally (`Pkg.test()`)
- [ ] Code is formatted (`JuliaFormatter.format()`)
- [ ] New functions have docstrings
- [ ] CHANGELOG.md is updated (for user-facing changes)
- [ ] No new dependencies unless necessary
- [ ] Wire format compatibility preserved

### Commit messages

Follow conventional commits:

```
feat: add Redis backend for high-throughput IPC
fix: handle empty file in concore_read gracefully
docs: add shared memory backend guide
test: add interop tests for numpy float32 values
refactor: extract file polling into separate function
```

## Julia Conventions

### Mutation convention

Functions that modify their arguments or global state end with `!`:

```julia
concore_init!()      # Modifies global state
load_iport!()        # Modifies global iport dict
default_maxtime!(n)  # Modifies global maxtime
```

### Docstrings

Use the standard Julia docstring format:

```julia
"""
    concore_read(port::Int, name::String, initstr::String) -> Vector{Float64}

Read data from input port `port`, file `name`. Falls back to `initstr` if
the file does not exist.

# Arguments
- `port::Int`: Input port number
- `name::String`: File name within the port directory
- `initstr::String`: Fallback value in wire format

# Returns
- `Vector{Float64}`: Parsed data values (without simtime)

# Examples
```julia
y = concore_read(1, "y", "[0.0, 0.0]")
```
"""
```

### Error handling

- Use typed `catch e` blocks, never bare `catch`
- Log caught errors with `@debug` or `@warn`
- Throw descriptive errors for unrecoverable conditions

```julia
# Good
try
    data = read(filepath, String)
catch e
    e isa SystemError || rethrow()
    @debug "File not found, using fallback" filepath exception=e
    data = fallback
end

# Bad -- never do this
try
    data = read(filepath, String)
catch
    data = fallback
end
```

### Type annotations

- Annotate function signatures for documentation and dispatch
- Avoid over-constraining argument types (use duck typing where appropriate)
- Annotate return types for clarity in public API

```julia
# Good: clear signature, flexible input
function safe_parse_list(str::AbstractString)::Vector{Float64}

# Avoid: over-constrained
function safe_parse_list(str::String)::Vector{Float64}
```

## Questions?

- Open an [issue](https://github.com/ControlCore-Project/concore/issues) for bugs or feature requests
- See the [CONTROL-CORE documentation](https://github.com/ControlCore-Project/concore) for protocol details
- Reach out to the maintainers for guidance on larger contributions
