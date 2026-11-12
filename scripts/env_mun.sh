# Environment on the AMD cluster (login node muncl01; partitions MI210, MI250, MI300A, MI300X):
# AFAR 24.3.0 (amdflang, OpenMP offload, HIP), its Open MPI (UCX 1.22.0), CMake, fypp.
# Usage: source scripts/env_mun.sh
module load afar/24.3.0 openmpi/afar-24.3.0/5.0.11 cmake/3.31.7 >/dev/null 2>&1
export LC_ALL=C
export OMPI_FC=amdflang         # the Open MPI wrappers call the flang of ROCm 7.2.2 otherwise
# fypp: pure Python, $HOME/fypp/fypp.py (from pip install fypp) + wrapper $HOME/fypp/bin/fypp,
# run by the system python3 (no venv/pip on the system Python)
export PATH=$HOME/fypp/bin:$PATH
# UCX with HIP VMM support: master 72895c480 + the draft ROCm VMM PRs openucx/ucx#12137, #12138,
# #12139, #12140 (built for stackdemo). UCX 1.22.0 of the Open MPI module takes HIP VMM memory
# (DOUBLESTACK_GPU) for host memory and segfaults. Loaded with LD_PRELOAD by the run scripts.
UCX_VMM=/home/marguina/bak1/ucx-vmm/install
UCX_PRELOAD=$UCX_VMM/lib/libucs.so.0:$UCX_VMM/lib/libucm.so.0:$UCX_VMM/lib/libuct.so.0:$UCX_VMM/lib/libucp.so.0
