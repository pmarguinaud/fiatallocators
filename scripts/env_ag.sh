# Environment on ag (GH200, aarch64): NVHPC 26.1, its HPC-X 2.25.1, CMake, fypp.
# Usage: source scripts/env_ag.sh
module load cmake/3.31.6 nvidia/26.1 >/dev/null 2>&1
export LC_ALL=C
NVHPC_ROOT=/usr/local/apps/nvidia/26.1/Linux_aarch64/26.1
source $NVHPC_ROOT/comm_libs/13.1/hpcx/latest/hpcx-init.sh
hpcx_load
export OMPI_FC=nvfortran        # the HPC-X wrappers of NVHPC 26.1 on aarch64 call gfortran
export PATH=$PERM/venv-fypp-aarch64/bin:$PATH
# UCX v1.23.x (contains openucx/ucx#12188, backport of #12186): needed for MPI on arrays that
# cross VMM chunks (DOUBLESTACK_GPU); loaded with LD_PRELOAD by the run scripts
UCX_NEW=/perm/sor/install/ucx-test/aarch64/ucx-v1.23.x
UCX_PRELOAD=$UCX_NEW/lib/libucs.so.0:$UCX_NEW/lib/libucm.so.0:$UCX_NEW/lib/libuct.so.0:$UCX_NEW/lib/libucp.so.0
