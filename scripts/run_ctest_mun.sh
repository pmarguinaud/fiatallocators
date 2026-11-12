#!/bin/bash
#SBATCH --job-name=fa_ctest
#SBATCH --partition=MI210
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:15:00
#SBATCH --output=ctest_%j.out
# Single-process tests (ctest) on one GPU of the AMD cluster.
#   sbatch [-p MI250|MI300A|MI300X] scripts/run_ctest_mun.sh [build_dir]
# The build must target the GPU of the partition (GPU_ARCH: gfx90a for MI210/MI250, gfx942 for
# MI300A/MI300X; "gfx90a,gfx942" for both).

cd ${SLURM_SUBMIT_DIR:-$(dirname $0)/..}
source scripts/env_mun.sh
BUILD=${1:-build_amd}
echo "=== node: $(hostname), partition ${SLURM_JOB_PARTITION}, job ${SLURM_JOB_ID}"
rocminfo | grep -m1 -E 'Marketing Name: *AMD Instinct'
cd $BUILD && timeout 600 ctest --timeout 120
