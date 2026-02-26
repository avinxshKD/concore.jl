# Contributing

Thank you for your interest in contributing to Concore.jl! Please see the [CONTRIBUTING.md](https://github.com/ControlCore-Project/concore/blob/main/concore-jl/CONTRIBUTING.md) file in the repository root for detailed guidelines.

## Quick Reference

### Setting up

```bash
git clone https://github.com/ControlCore-Project/concore.git
cd concore/concore-jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Running tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Code formatting

```bash
julia -e 'using JuliaFormatter; format("src/"); format("test/")'
```

### Building documentation locally

```bash
julia --project=docs/ -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs/ docs/make.jl
```

The built documentation will be in `docs/build/`.

## Areas for Contribution

- **New backends**: Implement additional IPC backends (e.g., Redis, ZeroMQ)
- **Performance**: Optimize the file polling and parsing paths
- **Examples**: Add more example controllers and plant models
- **Documentation**: Improve guides and add tutorials
- **Tests**: Increase test coverage, especially for edge cases
- **Interop**: Add cross-language test cases with Python/C++ nodes

See the full [CONTRIBUTING.md](https://github.com/ControlCore-Project/concore/blob/main/concore-jl/CONTRIBUTING.md) for code style guidelines, PR process, and Julia conventions.
