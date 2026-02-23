"""
concore.py -- Minimal Python concore module for cross-language demo

Self-contained file-based IPC module compatible with the Julia concore.jl.
Implements the same wire format and polling protocol.
No external dependencies -- only Python stdlib.
"""

# NOTE: This is a minimal subset of concore for demo purposes.
# It handles standard Python literal format only (not numpy annotations).
# For production use, use the full concore.py from the ControlCore-Project repo.

import ast
import os
import time

# Module-level globals
simtime = 0.0
delay = 1.0
maxtime = 100
retrycount = 0
s = ""
olds = ""
iport = {}
oport = {}
params = {}
inpath = "./in"
outpath = "./out"
_S_MAX_LEN = 65536


def _format_wire(vals):
    """Format a list of floats as concore wire-format string."""
    parts = []
    for v in vals:
        if isinstance(v, float) and v == int(v) and abs(v) < 1e15:
            parts.append(f"{int(v)}.0")
        else:
            parts.append(str(v))
    return "[" + ", ".join(parts) + "]"


def _parse_list(s_val):
    """Parse a concore wire-format string into a list of floats."""
    cleaned = s_val.strip()
    if not cleaned:
        raise ValueError("empty input")
    try:
        result = ast.literal_eval(cleaned)
        return [float(x) for x in result]
    except (ValueError, SyntaxError):
        raise ValueError(f"cannot parse: {cleaned[:80]}")


def _load_port_file(filename):
    """Parse a concore port config file."""
    try:
        with open(filename) as f:
            return ast.literal_eval(f.read().strip())
    except (FileNotFoundError, ValueError, SyntaxError):
        return {}


def _load_config():
    """Load port configs from filesystem."""
    global iport, oport
    iport = _load_port_file("concore.iport")
    oport = _load_port_file("concore.oport")


def default_maxtime(default):
    """Read max simulation time from in1/concore.maxtime, or use default."""
    global maxtime
    try:
        path = os.path.join(inpath + "1", "concore.maxtime")
        with open(path) as f:
            maxtime = int(f.read().strip())
    except (FileNotFoundError, ValueError):
        maxtime = default
    return maxtime


def read(port, name, initstr):
    """Read data from input port file. Returns data values (without simtime)."""
    global s, simtime, retrycount
    time.sleep(delay)
    filepath = os.path.join(inpath + str(port), name)
    ins = ""
    try:
        with open(filepath) as f:
            ins = f.read()
    except FileNotFoundError:
        ins = initstr
    attempts = 0
    while not ins and attempts < 5:
        time.sleep(delay)
        try:
            with open(filepath) as f:
                ins = f.read()
        except FileNotFoundError:
            pass
        attempts += 1
        retrycount += 1
    if not ins:
        ins = initstr
    s = (s + ins)[-_S_MAX_LEN:]
    val = _parse_list(ins)
    simtime = max(simtime, val[0])
    return val[1:]


def write(port, name, val, delta=0):
    """Write data to output port file."""
    global simtime
    filepath = os.path.join(outpath + str(port), name)
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    outval = [simtime + delta] + list(val)
    wire = _format_wire(outval)
    with open(filepath, "w") as f:
        f.write(wire)
    simtime += delta


def initval(simtime_val):
    """Parse initial value string, set simtime, return data portion."""
    global simtime
    val = _parse_list(simtime_val)
    simtime = val[0]
    return val[1:]


def unchanged():
    """Return True if no new data has been read since the last call."""
    global s, olds
    if olds == s:
        s = ""
        return True
    else:
        olds = s
        return False


try:
    _load_config()
except Exception:
    pass
