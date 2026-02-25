# API Reference

## Core Protocol

```@docs
concore_read
concore_write
initval
unchanged
safe_parse_list
```

## Configuration

```@docs
parse_port_file
load_iport!
load_oport!
load_params!
tryparam
default_maxtime!
concore_init!
```

## Types

```@docs
ConCoreContext
AbstractBackend
FileBackend
DockerBackend
SharedMemoryBackend
```

## Docker Support

```@docs
detect_environment
init_docker!
```

## Utilities

```@docs
Concore.ConcoreUtils.PIDController
Concore.ConcoreUtils.PIDState
Concore.ConcoreUtils.execute_step
Concore.ConcoreUtils.reset!
Concore.ConcoreUtils.load_graph
```
