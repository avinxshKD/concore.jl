#!/usr/bin/env python3
"""
mkconcore_julia_patch.py -- Documents ALL changes needed to add Julia (.jl)
support to mkconcore.py in the concore framework.

This file serves as a comprehensive patch reference. Each section below
corresponds to a specific location in mkconcore.py where changes are needed.

To apply: manually edit mkconcore.py following each section below, or use
this as a reference for automated patching.

Repository: https://github.com/ControlCore-Project/concore
Target file: concore/mkconcore.py
"""

# =============================================================================
# PATCH 1: Add Julia executable variables
# =============================================================================
# Location: Near line 14-15, after the existing executable variable definitions
#           (PYTHONEXE, PYTHONWIN, MATLABEXE, etc.)
#
# Context (existing code):
#   PYTHONEXE = "python3"   # Ubuntu Python3
#   PYTHONWIN = "python"    # Windows Python
#   MATLABEXE = "octave"    # Ubuntu Matlab / Octave
#   ...
#
# Add after the existing executable definitions:

PATCH_1_VARIABLES = """
JULIAEXE = "julia"      # Ubuntu/macOS Julia
JULIAWIN = "julia"      # Windows Julia
"""

# =============================================================================
# PATCH 2: Add "jl" to the language extension validation check
# =============================================================================
# Location: In the langext validation block (search for the list of
#           supported extensions)
#
# Change FROM:
#   if not (langext in ["py","m","sh","cpp","v"]):
#
# Change TO:
#   if not (langext in ["py","m","sh","cpp","v","jl"]):

PATCH_2_LANGEXT_CHECK = """
# BEFORE:
if not (langext in ["py","m","sh","cpp","v"]):

# AFTER:
if not (langext in ["py","m","sh","cpp","v","jl"]):
"""

# =============================================================================
# PATCH 3: Copy concore.jl library file into /src
# =============================================================================
# Location: After the section that copies concore.py (~line 380), in the
#           block that copies language-specific concore library files.
#
# Context: mkconcore.py copies the standalone concore library for each
#          language into the /src directory. For Python it copies concore.py
#          (or concoredocker.py for Docker). We need the same for Julia.
#
# Add after the concore.py copy block:

PATCH_3_COPY_CONCORE_JL = """
# Copy concore.jl for Julia support
try:
    if concoretype == "docker":
        fsource = open(CONCOREPATH + "/standalone/concoredocker.jl")
    else:
        fsource = open(CONCOREPATH + "/standalone/concore.jl")
except:
    logging.warning(f"Julia concore library not found at {CONCOREPATH}")
else:
    with open(outdir + "/src/concore.jl", "w") as fcopy:
        fcopy.write(fsource.read())
    fsource.close()
"""

# =============================================================================
# PATCH 4: Build script -- copy concore.jl into node directory
# =============================================================================
# Location: In the build script generation section, where language-specific
#           files are copied into each container/node directory.
#
# Context (existing patterns):
#   if langext == "py":
#       fbuild.write("cp ./src/concore.py ./" + containername + "/concore.py\n")
#   elif langext == "cpp":
#       fbuild.write("cp ./src/concore.hpp ./" + containername + "/concore.hpp\n")
#
# === POSIX (Linux/macOS) build script ===

PATCH_4A_BUILD_POSIX = """
elif langext == "jl":
    fbuild.write("cp ./src/concore.jl ./" + containername + "/concore.jl\\n")
"""

# === Windows build script ===

PATCH_4B_BUILD_WINDOWS = """
elif langext == "jl":
    fbuild.write("copy .\\\\src\\\\concore.jl .\\\\" + containername + "\\\\concore.jl\\n")
"""

# =============================================================================
# PATCH 5: Run script -- execute Julia nodes
# =============================================================================
# Location: In the run/debug script generation section, where each language
#           gets its execution command.
#
# Context (existing patterns):
#   if langext == "py":
#       frun.write('(cd "' + containername + '"; ' + PYTHONEXE + ' ...')
#
# === POSIX run script (background execution) ===

PATCH_5A_RUN_POSIX = """
elif langext == "jl":
    frun.write('(cd "' + containername + '"; ' + JULIAEXE + ' ' + sourcecode + ' >concoreout.txt & echo $! >concorepid) &\\n')
"""

# === POSIX debug script (Linux/Ubuntu -- xterm) ===

PATCH_5B_DEBUG_POSIX_LINUX = """
elif langext == "jl":
    fdebug.write('concorewd="$(pwd)"\\n')
    fdebug.write('xterm -e bash -c "cd \\\\"$concorewd/' + containername + '\\\\"; ' + JULIAEXE + ' ' + sourcecode + '; bash" &\\n')
"""

# === POSIX debug script (macOS -- Terminal.app via osascript) ===

PATCH_5C_DEBUG_POSIX_MACOS = """
elif langext == "jl":
    fdebug.write('concorewd="$(pwd)"\\n')
    fdebug.write('osascript -e "tell application \\\\"Terminal\\\\" to do script \\\\"cd \\\\\\\\\\\\"$concorewd/' + containername + '\\\\\\\\\\\\"; ' + JULIAEXE + ' ' + sourcecode + '\\\\"" \\n')
"""

# === Windows run script ===

PATCH_5D_RUN_WINDOWS = """
elif langext == "jl":
    frun.write('start /B /D '+containername+" "+JULIAWIN+" "+sourcecode+" >"+containername+"\\\\concoreout.txt\\n")
"""

# === Windows debug script ===

PATCH_5E_DEBUG_WINDOWS = """
elif langext == "jl":
    fdebug.write('start /D '+containername+" cmd /K "+JULIAWIN+" "+sourcecode+"\\n")
"""

# =============================================================================
# PATCH 6: Docker support -- Dockerfile template and CMD
# =============================================================================
# Location: In the Docker build section, where language-specific Dockerfiles
#           are selected.
#
# Context (existing patterns):
#   if langext == "py":
#       fsource = open(CONCOREPATH + "/Dockerfile.py")
#   elif langext == "cpp":
#       fsource = open(CONCOREPATH + "/Dockerfile.cpp")
#
# === Select Julia Dockerfile template ===

PATCH_6A_DOCKERFILE_SELECT = """
elif langext == "jl":
    fsource = open(CONCOREPATH + "/Dockerfile.jl")
    logging.info("assuming .jl extension for Dockerfile")
"""

# === Append CMD to Dockerfile ===
# Location: After the Dockerfile template is copied, where the CMD line
#           is appended based on language.
#
# Context:
#   if langext == "py":
#       fcopy.write('CMD ["python3", "' + sourcecode + '"]\\n')

PATCH_6B_DOCKERFILE_CMD = """
if langext == "jl":
    fcopy.write('CMD ["julia", "' + sourcecode + '"]\\n')
"""

# =============================================================================
# PATCH 7: Stop script -- no Julia-specific changes needed
# =============================================================================
# The stop script uses generic process killing (via PID files or container
# names), so no language-specific changes are needed for Julia.

PATCH_7_STOP = """
# No Julia-specific changes needed in stop script generation.
# The existing PID-based and container-based stop mechanisms are language-agnostic.
"""


# =============================================================================
# SUMMARY OF ALL CHANGES
# =============================================================================

SUMMARY = """
Summary of changes needed in mkconcore.py for Julia (.jl) support:

1. EXECUTABLE VARIABLES (top of file, ~line 14-15):
   - Add JULIAEXE = "julia"
   - Add JULIAWIN = "julia"

2. LANGUAGE EXTENSION CHECK:
   - Add "jl" to the supported extensions list

3. LIBRARY FILE COPY (src/ setup, ~line 380):
   - Copy standalone/concore.jl (or standalone/concoredocker.jl for Docker)
     into outdir/src/concore.jl

4. BUILD SCRIPT (file copy into node dirs):
   - POSIX: cp ./src/concore.jl ./{containername}/concore.jl
   - Windows: copy .\\src\\concore.jl .\\{containername}\\concore.jl

5. RUN/DEBUG SCRIPTS:
   - POSIX run: (cd "{name}"; julia script.jl >concoreout.txt & echo $! >concorepid) &
   - POSIX debug (Linux): xterm with julia
   - POSIX debug (macOS): osascript Terminal.app with julia
   - Windows run: start /B /D {name} julia script.jl
   - Windows debug: start /D {name} cmd /K julia script.jl

6. DOCKER:
   - Select Dockerfile.jl template for .jl files
   - Append CMD ["julia", "script.jl"] to generated Dockerfile

7. STOP SCRIPT:
   - No changes needed (language-agnostic)

Files required in the concore repository:
   - standalone/concore.jl       -- Standalone module with relative paths (./in, ./out)
   - standalone/concoredocker.jl -- Standalone module with Docker paths (/in, /out)
   - Dockerfile.jl               -- Docker template for Julia nodes
"""

if __name__ == "__main__":
    print(SUMMARY)
    print("\nSee each PATCH_* variable in this file for exact code changes.")
    print("Total patches: 7 sections (some with sub-patches for POSIX/Windows/macOS)")
