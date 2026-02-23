#!/bin/bash
# Cross-language demo: Julia controller + Python plant model
# Demonstrates concore interoperability between Julia and Python nodes.
#
# Usage:
#     bash demo/cross_language/run_cross_language.sh
#
# Requirements:
#     - Julia (any recent version)
#     - Python 3 (stdlib only)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Concore Cross-Language Demo ==="
echo "Julia controller <-> Python plant model"
echo ""

# Create workspace
WORKSPACE=$(mktemp -d)
echo "Workspace: $WORKSPACE"

# Create edge directories (shared data channels)
mkdir -p "$WORKSPACE/CU"
mkdir -p "$WORKSPACE/PYM"

# ── Controller node (Julia) ──────────────────────────────────────────────────

mkdir -p "$WORKSPACE/CZ"
cp "$SCRIPT_DIR/controller.jl" "$WORKSPACE/CZ/"
cp "$REPO_ROOT/standalone/concore.jl" "$WORKSPACE/CZ/concore.jl"

# Port config: reads from PYM edge on port 1, writes to CU edge on port 1
echo "{'PYM': 1}" > "$WORKSPACE/CZ/concore.iport"
echo "{'CU': 1}" > "$WORKSPACE/CZ/concore.oport"

# Symlinks: in1 -> PYM (measurement input), out1 -> CU (control output)
ln -s "$WORKSPACE/PYM" "$WORKSPACE/CZ/in1"
ln -s "$WORKSPACE/CU" "$WORKSPACE/CZ/out1"

# ── Plant model node (Python) ───────────────────────────────────────────────

mkdir -p "$WORKSPACE/PZ"
cp "$SCRIPT_DIR/pm.py" "$WORKSPACE/PZ/"
cp "$SCRIPT_DIR/concore.py" "$WORKSPACE/PZ/"

# Port config: reads from CU edge on port 1, writes to PYM edge on port 1
echo "{'CU': 1}" > "$WORKSPACE/PZ/concore.iport"
echo "{'PYM': 1}" > "$WORKSPACE/PZ/concore.oport"

# Symlinks: in1 -> CU (control input), out1 -> PYM (measurement output)
ln -s "$WORKSPACE/CU" "$WORKSPACE/PZ/in1"
ln -s "$WORKSPACE/PYM" "$WORKSPACE/PZ/out1"

# ── Initial data and maxtime ────────────────────────────────────────────────

echo "[0.0, 0.0]" > "$WORKSPACE/CU/u"
echo "[0.0, 0.0]" > "$WORKSPACE/PYM/ym"

echo "20" > "$WORKSPACE/CU/concore.maxtime"
echo "20" > "$WORKSPACE/PYM/concore.maxtime"

# ── Launch processes ────────────────────────────────────────────────────────

echo "Starting Julia controller..."
(cd "$WORKSPACE/CZ" && julia controller.jl > concoreout.txt 2>&1 & echo $! > concorepid)

echo "Starting Python plant model..."
(cd "$WORKSPACE/PZ" && python3 pm.py > concoreout.txt 2>&1 & echo $! > concorepid)

echo "Waiting for simulation to complete..."

# Wait with timeout
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    CZ_PID=$(cat "$WORKSPACE/CZ/concorepid" 2>/dev/null || echo "")
    PZ_PID=$(cat "$WORKSPACE/PZ/concorepid" 2>/dev/null || echo "")

    CZ_RUNNING=false
    PZ_RUNNING=false
    [ -n "$CZ_PID" ] && kill -0 "$CZ_PID" 2>/dev/null && CZ_RUNNING=true
    [ -n "$PZ_PID" ] && kill -0 "$PZ_PID" 2>/dev/null && PZ_RUNNING=true

    if ! $CZ_RUNNING && ! $PZ_RUNNING; then
        echo "Both processes completed."
        break
    fi

    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "TIMEOUT! Killing processes..."
    kill -9 $(cat "$WORKSPACE/CZ/concorepid" 2>/dev/null) 2>/dev/null || true
    kill -9 $(cat "$WORKSPACE/PZ/concorepid" 2>/dev/null) 2>/dev/null || true
fi

# ── Results ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Controller Output (Julia) ==="
cat "$WORKSPACE/CZ/concoreout.txt" 2>/dev/null || echo "(no output)"

echo ""
echo "=== Plant Model Output (Python) ==="
cat "$WORKSPACE/PZ/concoreout.txt" 2>/dev/null || echo "(no output)"

echo ""
echo "=== Final Data Files ==="
echo "CU/u: $(cat "$WORKSPACE/CU/u" 2>/dev/null || echo 'empty')"
echo "PYM/ym: $(cat "$WORKSPACE/PYM/ym" 2>/dev/null || echo 'empty')"

# Cleanup
rm -rf "$WORKSPACE"
echo ""
echo "Done!"
