"""
pm.py -- Plant model node for cross-language demo

Python plant model that communicates with a Julia controller via concore
file-based IPC. Demonstrates cross-language interoperability.

Run from the node working directory (e.g., PZ/):
    python3 pm.py
"""

import concore


def pm(u):
    """Simple plant model: adds 0.01 to input."""
    return [v + 0.01 for v in u]


concore.default_maxtime(150)
concore.delay = 0.02

init_simtime_u = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

ym = concore.initval(init_simtime_ym)
u = concore.initval(init_simtime_u)

while concore.simtime < concore.maxtime:
    while concore.unchanged():
        u = concore.read(1, "u", init_simtime_u)
    ym = pm(u)
    print(f"{concore.simtime}. u={u} ym={ym}")
    concore.write(1, "ym", ym, delta=1)

print(f"retry={concore.retrycount}")
