# Dockerfile template for Julia concore nodes
# Used by mkconcore.py when building Docker images for .jl nodes
#
# mkconcore.py appends a CMD line based on the source file, e.g.:
#   CMD ["julia", "scriptname.jl"]

FROM julia:1.10-bullseye

LABEL description="Julia concore node for CONTROL-CORE studies"

WORKDIR /src

# concore Docker convention: /in{port}/ and /out{port}/ directories
# These are bind-mounted as volumes by the study runner
RUN mkdir -p /in1 /out1

# Copy all files from the build context (node script + concoredocker.jl)
COPY . /src
