#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# run_all_demos.sh -- Automated demo runner for video recording
#
# Run this while screen recording to produce the video demo.
# Each section prints a header, shows the command, runs it, and pauses
# for the presenter to narrate.
#
# Usage:
#     chmod +x demo/video/run_all_demos.sh
#     ./demo/video/run_all_demos.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Colors and formatting ────────────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─── Helper functions ─────────────────────────────────────────────────────────

pause() {
    echo ""
    echo -e "${YELLOW}>>> Press Enter to continue...${NC}"
    read -r
}

section() {
    echo ""
    echo ""
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

subsection() {
    echo ""
    echo -e "${BOLD}${CYAN}── $1 ──${NC}"
    echo ""
}

show_cmd() {
    echo -e "${DIM}\$ ${MAGENTA}$1${NC}"
    echo ""
}

run_cmd() {
    show_cmd "$1"
    eval "$1"
}

run_julia() {
    show_cmd "julia --project=$REPO_ROOT $1"
    julia --project="$REPO_ROOT" "$1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# DEMO START
# ═══════════════════════════════════════════════════════════════════════════════

clear
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                                                              ║${NC}"
echo -e "${BOLD}${GREEN}║              Concore.jl - Video Demo                         ║${NC}"
echo -e "${BOLD}${GREEN}║         Julia Reference Implementation of CONTROL-CORE       ║${NC}"
echo -e "${BOLD}${GREEN}║                                                              ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}Repository: $REPO_ROOT${NC}"
echo -e "  ${DIM}Date: $(date '+%Y-%m-%d %H:%M')${NC}"
echo ""

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 2: Package Overview
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 2: Package Overview"

subsection "Repository Structure"
run_cmd "ls $REPO_ROOT"
echo ""

subsection "Source Files"
run_cmd "ls $REPO_ROOT/src/"
echo ""

subsection "Project.toml"
run_cmd "cat $REPO_ROOT/Project.toml"
echo ""

subsection "Test Count"
echo -e "${GREEN}Total @test assertions:${NC}"
grep -r "@test" "$REPO_ROOT/test/" --include="*.jl" 2>/dev/null | wc -l | xargs echo " "
echo ""

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 3: Core API Demo
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 3: Core API Demo"

subsection "Running REPL Demo Script"
run_julia "$SCRIPT_DIR/repl_demo.jl"

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 4: Multi-Process Control Loop
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 4: Multi-Process Control Loop"

subsection "Controller Node (demo/controller.jl)"
echo -e "${DIM}--- Bang-bang controller: increase 1% below setpoint, decrease 10% above ---${NC}"
echo ""
run_cmd "head -30 $REPO_ROOT/demo/controller.jl"
echo ""

subsection "Plant Model Node (demo/pm.jl)"
echo -e "${DIM}--- Simple plant: adds 0.01 to input ---${NC}"
echo ""
run_cmd "head -25 $REPO_ROOT/demo/pm.jl"
echo ""

pause

subsection "Running Multi-Process Demo (maxtime=15)"
echo -e "${DIM}Two separate Julia processes communicating via file-based IPC${NC}"
echo ""
run_julia "$REPO_ROOT/demo/run_demo.jl 15"

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 5: Cross-Language Interop
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 5: Cross-Language Interoperability"

subsection "Running Cross-Language Test"
echo -e "${DIM}Proves Julia reads Python format and writes Python-compatible output${NC}"
echo ""
run_julia "$REPO_ROOT/examples/cross_language_test.jl"

pause

subsection "Running Python Interop Demo"
echo -e "${DIM}Simulated concore study: Julia controller with Python plant data${NC}"
echo ""
run_julia "$REPO_ROOT/examples/python_interop_demo.jl"

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 6: Performance Benchmarks
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 6: Performance Benchmarks"

subsection "Parser Benchmarks"
echo -e "${DIM}Wire format parsing: standard lists, numpy wrappers, formatting${NC}"
echo ""
run_julia "$REPO_ROOT/benchmark/bench_parser.jl"
echo ""

subsection "File I/O Benchmarks"
echo -e "${DIM}Raw file write/read throughput using concore protocol${NC}"
echo ""
run_julia "$REPO_ROOT/benchmark/bench_io.jl"

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 7: Advanced Features
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 7: Advanced Features"

subsection "Backend Type Hierarchy"
julia --project="$REPO_ROOT" -e '
using Concore
println("AbstractBackend subtypes:")
for T in [FileBackend, DockerBackend, SharedMemoryBackend]
    println("  $T <: AbstractBackend = $(T <: AbstractBackend)")
end
println()
println("Instances:")
println("  FileBackend()             = $(FileBackend())")
println("  DockerBackend()           = $(DockerBackend())")
println("  SharedMemoryBackend()     = $(SharedMemoryBackend())")
println("  SharedMemoryBackend(8192) = $(SharedMemoryBackend(8192))")
println()
println("Context-based API:")
ctx = ConCoreContext(backend=SharedMemoryBackend(), delay=0.01, maxtime=50)
println("  $ctx")
'

pause

# ═══════════════════════════════════════════════════════════════════════════════
# PART 8: Closing
# ═══════════════════════════════════════════════════════════════════════════════

section "PART 8: Summary"

echo -e "${GREEN}Concore.jl -- Julia Reference Implementation${NC}"
echo ""
echo "  - Safe wire format parser (regex-based, no eval)"
echo "  - File-based, shared memory, and ZeroMQ backends"
echo "  - 902+ test assertions"
echo "  - Full API documentation with docstrings"
echo "  - Docker container support"
echo "  - Cross-language interoperability (Python compatible)"
echo "  - Microsecond-scale performance"
echo "  - Julia 1.8+ compatible"
echo ""
echo -e "${BOLD}${GREEN}Ready for integration into the concore ecosystem.${NC}"
echo ""

echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}  Demo Complete                                            ${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
