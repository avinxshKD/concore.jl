# Dockerfile for running Julia concore nodes in Docker
# Matches the concoredocker.py pattern for containerized studies

FROM julia:1.10-bullseye

LABEL maintainer="Avinash Kumar Deepak"
LABEL description="Julia concore node for CONTROL-CORE studies"
LABEL org.opencontainers.image.source="https://github.com/ControlCore-Project/concore"

# Install the package
WORKDIR /app
COPY Project.toml .
COPY src/ src/

RUN julia -e 'using Pkg; Pkg.activate("."); Pkg.instantiate(); Pkg.precompile()'

# concore Docker convention: /in{port}/ and /out{port}/ directories
# These are mounted as volumes by the study runner
RUN mkdir -p /in1 /out1

# Default entrypoint runs a Julia script passed as argument
ENTRYPOINT ["julia", "--project=/app"]
CMD ["--help"]
