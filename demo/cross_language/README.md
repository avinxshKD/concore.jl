# Cross-Language Demo: Julia Controller + Python Plant Model

Demonstrates concore's cross-language interoperability by running a Julia
controller node and a Python plant model node in the same study.

## Architecture

```
Julia (controller.jl)          Python (pm.py)
     |                              |
     |--- CU/u (control signal) --->|
     |                              |
     |<-- PYM/ym (measurement) -----|
```

- **controller.jl** -- Bang-bang controller (Julia, using standalone concore.jl)
- **pm.py** -- Plant model `ym = u + 0.01` (Python, using minimal concore.py)
- **concore.py** -- Minimal Python concore module (stdlib only, ~140 lines)

Both nodes use identical file-based IPC. The wire format (`[simtime, v1, v2, ...]`)
is shared across all concore language implementations.

## Running

```bash
bash demo/cross_language/run_cross_language.sh
```

Requires Julia and Python 3 (stdlib only, no pip packages).

## What This Proves

1. Julia and Python nodes exchange data via the same wire format
2. The concore polling protocol works identically across languages
3. No shared runtime or FFI needed -- just filesystem IPC
