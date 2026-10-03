# GENESIS 2.5, the CPU-only reproduction path in a container (reviewer point 11:
# the hardware-independent results of the paper, reproducible without installing
# anything). The GPU results need a CUDA machine and are not built here.
#
#   docker build -t genesis25-cpu .
#   docker run --rm genesis25-cpu                   # ~2 min: the quick CPU claims,
#                                                   # each printed beside its
#                                                   # published value with a verdict
#   docker run --rm genesis25-cpu \
#       sh reproduce/run_all.sh --cpu-only          # ~90 min: full replicate counts
#   docker run --rm -v "$PWD/results:/genesis/reproduce/results" genesis25-cpu
#                                                   # keep the raw CSVs and logs
#
# The same path runs on every push in .github/workflows/cpu-only.yml, and this
# image is rebuilt and run there too, so the container is tested continuously.
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential flex bison libncurses-dev python3 \
    && rm -rf /var/lib/apt/lists/*

COPY . /genesis
WORKDIR /genesis

# Build the CPU binary once, into the image; runs then skip it (SKIP_BUILD).
RUN sh cluster_bringup/12_build_cpu.sh
ENV SKIP_BUILD=1

CMD ["sh", "reproduce/run_all.sh", "--cpu-only", "--quick"]
