#!/bin/sh
# Build the three binaries a campaign node needs, in the order that keeps all
# of them: the OpenCL build first (it leaves nxgenesis_ocl), then the CUDA
# build for this node's card (nxgenesis, nxgenesis_nocl). Run on the GPU node,
# from the checkout the campaign will run in; every node needs its own
# checkout, because the CUDA build targets the card it runs on.
#
#     sh cluster_bringup/campaign/prepare_node.sh
#
# Writes the build logs and the binaries' checksums to
# logs/campaign_<tag or dry>/build_<node>/, so the reports can name exactly
# which binaries produced them.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$GENESIS_ROOT" || exit 2
NODE=$(hostname -s)
TAG=${CAMPAIGN_TAG:-v2.6.0-rc1}
OUT=cluster_bringup/logs/campaign_$TAG/build_$NODE
[ "${CAMPAIGN_DRY:-0}" = 1 ] && OUT=cluster_bringup/logs/campaign_dry/build_$NODE
mkdir -p "$OUT"
echo "commit $(git rev-parse HEAD) ($(git describe --tags --always)) on $NODE" | tee "$OUT/summary.txt"
sh cluster_bringup/11_build_opencl.sh > "$OUT/build_opencl.log" 2>&1 \
    || { echo "OpenCL build failed, see $OUT/build_opencl.log" | tee -a "$OUT/summary.txt"; exit 1; }
sh cluster_bringup/10_build.sh > "$OUT/build_cuda.log" 2>&1 \
    || { echo "CUDA build failed, see $OUT/build_cuda.log" | tee -a "$OUT/summary.txt"; exit 1; }
for b in nxgenesis nxgenesis_nocl nxgenesis_ocl; do
    [ -x "genesis/src/$b" ] || { echo "missing genesis/src/$b after the builds" | tee -a "$OUT/summary.txt"; exit 1; }
done
( cd genesis/src && sha256sum nxgenesis nxgenesis_nocl nxgenesis_ocl ) | tee "$OUT/binaries.sha256"
"$CUDA_HOME/bin/cuobjdump" --list-elf genesis/src/nxgenesis 2>/dev/null | grep -o 'sm_[0-9]*' | sort -u \
    | sed 's/^/native code: /' | tee -a "$OUT/summary.txt"
gzip -9f "$OUT"/build_*.log
echo "ready" | tee -a "$OUT/summary.txt"
