#!/bin/bash
#SBATCH --job-name=fa_test_mpi
#SBATCH --partition=MI210
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:2
#SBATCH --cpus-per-task=8
#SBATCH --time=00:20:00
#SBATCH --output=test_mpi_%j.out
# Test f on the AMD cluster: test_mpi with 2 ranks, 1 GPU each, for every allocator, CPU and GPU.
# Every partition has a single node, so both ranks run on the same node (GPU to GPU through
# UCX rocm_ipc, not through the network). MI210: only electra019 has 2 GPUs.
# The UCX of the Open MPI module (1.22.0) is replaced by the UCX with HIP VMM support of
# env_mun.sh (LD_PRELOAD), needed by DOUBLESTACK_GPU. To run with UCX 1.22.0:
#   sbatch --export=ALL,UCX_PRELOAD_FA=none scripts/run_mpi_mun.sh
# Build first (build_amd with -DENABLE_GPU=ON -DENABLE_MPI=ON), then, from the repo directory:
#   sbatch scripts/run_mpi_mun.sh [build_dir]
#   sbatch -p MI250 scripts/run_mpi_mun.sh build_amd      (other partition)
# Extra mpirun options can be given in MPIRUN_OPTS (e.g. -x UCX_TLS=...).

cd ${SLURM_SUBMIT_DIR:-$(dirname $0)/..}
source scripts/env_mun.sh
BUILD=${1:-build_amd}
# The Open MPI module loads openmpi-rt/ucx, which sets UCX_TLS=sm,dc_x and UCX_NET_DEVICES=mlx5_0:1:
# that leaves out the ROCm transports (GPU buffers), and fails on nodes without InfiniBand
# (MI300A). Both ranks are on the same node: shared memory, ROCm copy and IPC.
export UCX_TLS=${UCX_TLS_FA:-self,sm,rocm}
unset UCX_NET_DEVICES
[ "$UCX_PRELOAD_FA" = none ] && UCX_PRELOAD=
echo "=== node: $(hostname), partition ${SLURM_JOB_PARTITION}, job ${SLURM_JOB_ID}"
UCXV=$(LD_PRELOAD=$UCX_PRELOAD ucx_info -v | grep 'Library path' | sed 's/.*path: //')
echo "=== $(ompi_info --version | head -1), UCX $UCXV, UCX_TLS=$UCX_TLS"

NFAIL=0
for SIDE in cpu gpu; do
  for KIND in doublestack fixed peak; do
    echo "=== test_mpi $KIND $SIDE"
    timeout -k 10 120 mpirun -n 2 --bind-to none -x LD_LIBRARY_PATH -x UCX_TLS \
      -x LD_PRELOAD=$UCX_PRELOAD $MPIRUN_OPTS $BUILD/tests/test_mpi $KIND $SIDE
    RC=$?
    echo "=== test_mpi $KIND $SIDE: exit code $RC"
    [ $RC -ne 0 ] && NFAIL=$((NFAIL + 1))
  done
done
echo "=== $NFAIL failed run(s)"
