# Changelog

All notable changes to Concore.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-03-03

### Added
- `ConCoreContext` type for explicit state management
- Backend system: `FileBackend`, `DockerBackend`, `SharedMemoryBackend`
- Docker support with `detect_environment()` and `init_docker!()`
- Shared memory IPC via memory-mapped files (Mmap.jl)
- Comprehensive test suite (300+ tests)
- CI/CD with GitHub Actions (Julia 1.8, latest, nightly; Linux, macOS, Windows)
- API documentation with Documenter.jl
- Anti-windup PID controller with `PIDController`/`PIDState` split
- `CONTRIBUTING.md` and `CHANGELOG.md`
- `LICENSE` file (LGPL-2.1)
- `.JuliaFormatter.toml` code style configuration
- Proper Julia package structure with `test/runtests.jl`

### Changed
- Flattened directory structure (removed nested `concore.jl/concore-jl/`)
- Replaced bare `catch` blocks with typed `catch e` + `@debug` logging
- Fixed `s` string accumulation bug (now capped at 65536 chars)
- Generated proper package UUID
- `ConcoreUtils` is now a proper submodule included from main module
- Function names follow Julia mutation convention (`concore_init!`, `default_maxtime!`, `load_iport!`)
- Split source into focused files: types.jl, parser.jl, config.jl, protocol.jl, docker.jl, shm.jl
- PID controller split into immutable `PIDController` + mutable `PIDState`

### Fixed
- Unbounded `s` string growth in `concore_read` (memory leak)
- Silent error swallowing in bare `catch` blocks
- Fabricated UUID in Project.toml

## [0.2.0] - 2026-02-25

### Added
- Safe regex-based parser (replaced `eval`/`Meta.parse`)
- Cross-language interoperability tests
- Python interop demo
- `ConcoreUtils` module with PID controller and GraphML parsing
- Comprehensive README with API mapping table

### Changed
- Separated PID/GraphML from core protocol
- Removed `FileWatching` dependency

## [0.1.0] - 2026-01-29

### Added
- Initial implementation of concore file-based IPC protocol
- Basic read, write, initval, unchanged functions
- Port config and parameter parsing
