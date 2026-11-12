#!/bin/bash
#SBATCH --job-name=fa_test_mpi
#SBATCH --partition=gpu
#SBATCH --qos=ng
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=00:20:00
#SBATCH --output=test_mpi_%j.out
# Test f on ag: test_mpi on 2 nodes, 1 GPU each, for every allocator, CPU and GPU.
# Build first (build_gpu with -DENABLE_GPU=ON -DENABLE_MPI=ON), then, from the repo directory:
#   sbatch scripts/run_mpi_ag.sh [build_dir]
# The UCX of HPC-X is replaced by UCX v1.23.x (LD_PRELOAD), needed by DOUBLESTACK_GPU (arrays
# crossing VMM chunks). --bind-to none: Open MPI cannot bind rank 0 on ag otherwise.

cd ${SLURM_SUBMIT_DIR:-$(dirname $0)/..}
source scripts/env_ag.sh
BUILD=${1:-build_gpu}
echo "=== nodes: $(scontrol show hostnames $SLURM_JOB_NODELIST | tr '\n' ' ')"

NFAIL=0
for SIDE in cpu gpu; do
  for KIND in doublestack fixed peak; do
    echo "=== test_mpi $KIND $SIDE"
    timeout -k 10 120 mpirun -n 2 --bind-to none -x LD_LIBRARY_PATH -x LD_PRELOAD=$UCX_PRELOAD \
      $BUILD/tests/test_mpi $KIND $SIDE
    RC=$?
    echo "=== test_mpi $KIND $SIDE: exit code $RC"
    [ $RC -ne 0 ] && NFAIL=$((NFAIL + 1))
  done
done
echo "=== $NFAIL failed run(s)"
