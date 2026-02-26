# Cross-Language Interoperability

Concore.jl is designed to interoperate seamlessly with concore implementations in other languages (Python, C++, MATLAB). This page documents the wire format specification and testing strategies for multi-language studies.

## Wire Format Specification

All concore nodes communicate through text files containing a simple list format:

```
[simtime, value1, value2, ...]
```

### Rules

1. **Outer brackets**: The string must start with `[` and end with `]`
2. **Comma-separated**: Values are separated by `, ` (comma followed by space)
3. **Floating-point**: All values are floating-point numbers with at least one decimal place
4. **First element**: Always the simulation timestamp (`simtime`)
5. **Remaining elements**: Application-specific data values

### Canonical Format

The canonical output format uses `.0` suffixes for integer-valued floats:

```
[0.0, 1.0, 2.5, -3.0]
```

This matches the Python `str([0.0, 1.0, 2.5, -3.0])` output format.

### Formatting Rules for Output

Concore.jl formats output values to match Python's behavior:

| Value | Julia Output | Python Output | Match? |
|-------|-------------|---------------|--------|
| `0.0` | `0.0` | `0.0` | Yes |
| `1.0` | `1.0` | `1.0` | Yes |
| `-3.0` | `-3.0` | `-3.0` | Yes |
| `2.5` | `2.5` | `2.5` | Yes |
| `3.14159` | `3.14159` | `3.14159` | Yes |

Integer-valued floats always include the `.0` suffix. Non-integer values are rounded to 15 significant digits to avoid IEEE 754 noise.

## Handling Numpy Annotations

Python nodes may produce numpy-annotated values. The `safe_parse_list` parser handles these transparently:

```julia
# All of these parse to [1.5]
safe_parse_list("[0.0, np.float64(1.5)]")
safe_parse_list("[0.0, numpy.float32(1.5)]")
safe_parse_list("[0.0, 1.5]")
```

### Supported numpy patterns

| Pattern | Parsed As |
|---------|-----------|
| `np.float64(1.5)` | `1.5` |
| `numpy.float32(1.5)` | `1.5` |
| `np.int64(3)` | `3.0` |
| `True` | `1.0` |
| `False` | `0.0` |
| `None` | `0.0` |

## Port Configuration Format

Port configurations are stored in `concore.iport` and `concore.oport` files using Python dict syntax:

```
{'e1': 1, 'e2': 2}
```

The `parse_port_file` function parses this format:

```julia
ports = parse_port_file("concore.iport")
# ports == Dict("e1" => 1, "e2" => 2)
```

### Format rules

- Outer braces: `{` and `}`
- Keys: Single-quoted strings (`'key'`)
- Values: Integers
- Separator: `, `

## Parameter Format

Parameters in `concore.params` support two formats:

### Python dict format

```
{'Kp': 2.0, 'Ki': 0.1, 'mode': 'auto'}
```

### Key-value format

```
Kp=2.0;Ki=0.1;mode=auto
```

Both formats are parsed by `load_params!` and accessible via `tryparam`.

## Testing Interoperability

### Bit-exact output comparison

The simplest interop test writes output from both Julia and Python nodes and compares:

```julia
# Julia side
concore_write(1, "test", [1.0, 2.5, -3.0]; delta=0)

# Read the file
julia_output = read("out1/test", String)
# julia_output == "[0.0, 1.0, 2.5, -3.0]"
```

```python
# Python side
concore.write(1, "test", [1.0, 2.5, -3.0])
```

Both should produce identical file contents.

### Round-trip test

Write from Python, read from Julia (or vice versa):

```julia
# Python writes "[5.0, 1.5, -2.3]" to in1/data
vals = concore_read(1, "data", "[0.0, 0.0, 0.0]")
# vals == [1.5, -2.3]
# Concore.simtime == 5.0
```

### Running interop tests

The test suite includes cross-language interoperability tests:

```bash
cd concore-jl
julia --project=. -e 'using Pkg; Pkg.test()'
```

To run interop tests that require Python:

```bash
cd concore-jl/examples
julia interop_test.jl
```

## Common Pitfalls

### Floating-point precision

Different languages may format floating-point numbers differently:

- Python: `str(1/3)` produces `0.3333333333333333`
- Julia: `string(1/3)` produces `0.3333333333333333`

Concore.jl rounds to 15 significant digits to minimize cross-language differences.

### Newlines

Some implementations may append a trailing newline. The parser strips whitespace before parsing, so this is handled automatically.

### File locking

The file-based protocol does not use file locks. Instead, it relies on:

1. Atomic writes (write to temp file, then rename) in some implementations
2. Polling with retry logic in readers
3. The `unchanged()` synchronization primitive

This design choice prioritizes simplicity and portability over strict consistency.

### Windows line endings

On Windows, files may contain `\r\n` line endings. The parser uses `strip()` which removes both `\r` and `\n`.
