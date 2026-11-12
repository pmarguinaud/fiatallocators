# AMD port: conclusions and questions

Answer under each **Answer:** line. The latest round comes first.

## Round 3 (2026-11-12): your answers applied

| Question | Your answer | Done |
|---|---|---|
| Q8 UCX location | keep it; document the exact version | `README.md` (AMD section) and `scripts/env_mun.sh`: UCX 1.24.0 (development), `/home/marguina/bak1/ucx-vmm/src`, branch `vmm-series` at `ff2fb9655` = master `72895c480` + #12137 (`12d45f12e`), #12138 (`b6839ad93`), #12139 (`8be6ca613`), #12140 (`0204c61b4`) |
| Q9 GEMM shape | good enough | unchanged |
| Q10 NVIDIA | ask the agent `port-cuda-to-hip-openmp` | message sent with the context and the checks to run on ag (build, ctest, `run_mpi_ag.sh`), on branch `amd-port`; it reports back to session `fiatallocators-a4` |
| Q11 commit | commit and push | committed on `amd-port` and pushed to `origin` |

No new questions this round. The next step is the NVIDIA check by the agent; I will report its
results here.

## Round 2 (2026-11-12): your answers applied

| Question | Your answer | Done |
|---|---|---|
| Q1 vendor selection | two modules | kept as is |
| Q2 MPI on `DOUBLESTACK_GPU` | right UCX, as in stackdemo | `scripts/env_mun.sh` defines `UCX_VMM=/home/marguina/bak1/ucx-vmm/install` (UCX master `72895c480` + #12137–#12140, built for stackdemo); `scripts/run_mpi_mun.sh` preloads it, as `run_mpi_ag.sh` does with UCX v1.23.x. `sbatch --export=ALL,UCX_PRELOAD_FA=none ...` runs with UCX 1.22.0 |
| Q3 graphs | GEMM kernels, as in stackdemo | new `tests/hip_graph_mod.F90`: same routines as `CUDA_GRAPH_MOD`, plus `GRAPH_ADD_ONE (X, U, V)`, which records `X = X + 1` as one `hipblasSgemm`, `X (1000, N) += U (1000, 16) * V (16, N)` with `U (:, 1) = 1`, `U (:, 2:) = 0`, `V = 1` (exact). Captured on a HIP stream, global mode. `test_graph` is built again on AMD, and `test_mpi` uses the graph on AMD too. `U` and `V` are arrays of the allocator |
| Q4 test name | rename | `test_acc` → `test_offload` (`git mv`) |
| Q5 | this file goes when the port is finished | |
| Q6 environment | acceptable | |
| Q7 commit | on another branch | branch `amd-port`, one commit (see Q11) |

Other change: `test_graph` now also checks that nothing ran during the capture (A and B
unchanged), for NVIDIA too.

### Results

| | MI210 | MI250 | MI300A | MI300X |
|---|---|---|---|---|
| ctest, 39 tests (CPU + GPU, `test_graph` included) | passed (9095) | passed (9097) | passed (9104) | passed (9105) |
| `test_mpi`, CPU and GPU, all 3 allocators | passed (9096) | passed (9103) | passed (9100) | passed (9102) |

- **Rerun jobs.** Jobs 9098, 9099 and 9101 were killed by signal 9 within the same 4 seconds
  (13:05:34–38), on three different nodes, each while another of my jobs ran on its node. They
  were not short of memory. Rerun one after another (9103, 9104, 9105), all three passed.
- **Logs:** `build_amd/logs/`.
- **NVIDIA:** still not built nor tested.

### New questions

#### Q8. Location of the patched UCX

It is in `/home/marguina/bak1/ucx-vmm/install`, but it was built for `/home/marguina/ucx-vmm/install`
(its `.pc` files still say so). Preloading by path works.

- Keep it there?
- Or move it, or rebuild it, in a permanent location (which one)?

**Answer:**

Keep it there, mention the exact version of UCX we have been using in the documentation

#### Q9. GEMM shape in the test graphs

Each graph node is one SGEMM with K = 16 that adds 1 to the array. This keeps the checks of
`test_graph` and `test_mpi` identical on both vendors.

- Enough?
- Or use grouped GEMMs with varying K and N, as in stackdemo, so that GEMM blocks cross chunk
  boundaries? The arrays A and B already cross them.

**Answer:**

Good enough.

#### Q10. NVIDIA

The changes to check on ag:

- `GPU_CREATE`/`GPU_DELETE`;
- CMake;
- the `#ifdef _OPENACC` in the tests;
- the new "nothing run during the capture" check in `test_graph`;
- the rename to `test_offload`.

Should I prepare a checklist for that run, or will you do it when you go back to NVIDIA?

**Answer:**

You will contact claude agent @port-cuda-to-hip-openmp, send him the context and tell him what to test


#### Q11. Commit

Everything is in one commit on branch `amd-port`: the AMD port, the `GPU_CREATE` interface change,
the build, the tests and the docs, including this file.

- Push it?
- Or split it?

**Answer:**


commit and push


---

# Round 1

Status on 2026-11-12. Answer under each **Answer:** line.

## 1. Setup

- **Machine:** login node muncl01 (no GPU). Partitions MI210, MI250, MI300A and MI300X, with a
  single node each.
- **Compiler:** AFAR 24.3.0 (amdflang, OpenMP offload).
- **MPI:** Open MPI 5.0.11 with UCX 1.22.0 (module `openmpi/afar-24.3.0/5.0.11`).
- **Environment:** `scripts/env_mun.sh`.
- **fypp:** in `~/fypp`, run by the system Python, which has no pip or venv.
- **Build:**
  `cmake -S . -B build_amd -DCMAKE_Fortran_COMPILER=amdflang -DCMAKE_C_COMPILER=amdclang -DENABLE_GPU=ON -DENABLE_MPI=ON -DGPU_ARCH=gfx90a`.
  `-DGPU_ARCH=gfx90a,gfx942` builds one binary for all four GPUs.

## 2. What changed

| File | Change |
|---|---|
| `src/gpu_helpers_amd.F90` (new) | same module name and public routines as the NVIDIA one; HIP VMM API + OpenMP runtime (`omp_target_associate_ptr`, `omp_target_alloc`), through `BIND (C)` |
| `src/gpu_helpers_nvidia.F90`, `src/peak_core_mod.F90`, `src/peak_gpu_mod.F90` | `GPU_CREATE` returns the device address; `GPU_DELETE (KHOST, KDEV, KBYTES)` takes it. `PEAK_ENTRY` stores it (`IDEV`), and `ON_ALLOC`/`ON_FREE` pass it |
| `CMakeLists.txt`, `src/CMakeLists.txt` | nvfortran or amdflang; `GPU_VENDOR` from the compiler by default; `GPU_ARCH` (AMD); `OFFLOAD_FLAGS`, `GPU_LIBRARIES` |
| `tests/test_acc.F90`, `test_types.fypp`, `test_debug.F90`, `test_mpi.F90` | OpenACC under `#ifdef _OPENACC`, OpenMP otherwise (`MAP (PRESENT, ALLOC: X)`, `TARGET UPDATE`, `TARGET DATA USE_DEVICE_ADDR`, `omp_target_is_present`, `omp_set_default_device`) |
| `tests/CMakeLists.txt` | `test_graph` built for NVIDIA only; new test `hip_vmm_layout` (AMD) |
| `tests/c/hip_vmm_layout.c` (new) | checks sizes, field offsets and enum values of the HIP structures against the ROCm headers |
| `scripts/env_mun.sh`, `scripts/run_ctest_mun.sh`, `scripts/run_mpi_mun.sh` (new) | environment, ctest job, MPI job (2 ranks on one node) |
| `README.md` | AMD section (status, limitations), build, tests, files |
| `src/doublestack_gpu_mod.F90`, `src/fixed_gpu_mod.F90` | comments only |

Points checked against the ROCm headers (porting note, §2.1):

- **Structure layout.** `hipMemAllocationProp` is 32 bytes. Its `allocFlags` field is **4 bytes**,
  not 8 as on CUDA: `gpuDirectRDMACapable` is the byte at offset 25.
- **Enum values.** Same as CUDA: pinned = 1, device location = 1, read/write access = 3.
  `hipDeviceAttributeVirtualMemoryManagementSupported` = 89.
- **VMM granularity.** 4 KiB on these GPUs.
- **Symbols.** All the HIP symbols are present, including `hipMemGetHandleForAddressRange`
  (needed for DMA-BUF).

## 3. Results

| | MI210 | MI250 | MI300A | MI300X |
|---|---|---|---|---|
| ctest, 36 tests (CPU + GPU) | passed | passed | passed | passed |
| `test_mpi`, CPU, all allocators | passed | passed | passed | passed |
| `test_mpi`, GPU, `fixed`, `peak` | passed | passed | passed | passed |
| `test_mpi`, GPU, `doublestack` | **segfault** | **segfault** | **segfault** | **segfault** |
| Slurm jobs (MPI) | 9086 | 9087 | 9088 | 9091 |

- **CPU-only build** with amdflang: 16 tests passed.
- **Expected failures** abort with the right message (LIFO violation, full buffer).
- **Logs:** `build_amd/logs/`.

## 4. Conclusions

1. **The design works on AMD.**
   - `omp_target_associate_ptr` accepts a 64 GiB range of device addresses of which only a part
     is mapped (`hipMemMap`).
   - OpenMP kernels run on arrays that cross chunk boundaries, on both sides.
   - `USE_DEVICE_ADDR` gives the device address.
   - On the MI300A, the explicit mapping works as on the discrete GPUs.

2. **OpenMP kernels cannot be captured into HIP graphs (AFAR 24.3.0).**
   - The offload runtime launches kernels on HSA queues, not on HIP streams.
   - A HIP stream capture (global mode) during a target region, synchronous or `NOWAIT`,
     records 0 nodes. The kernels run immediately, outside the graph.
   - `!$omp interop init (targetsync: obj)` returns `omp_interop_none`.
   - `DEPEND (INTEROPOBJ: ...)` is not parsed by flang.
   - As the porting note asks, the kernels were not rewritten in HIP.
   - Consequences: `test_graph` is built for NVIDIA only. On AMD, `test_mpi` launches the two
     kernels directly at each "replay".

3. **GPU-aware MPI works on `FIXED_GPU` and `PEAK_GPU` arrays, which are single allocations.**

4. **MPI on `DOUBLESTACK_GPU` arrays fails, at the first exchange.**
   - Backtrace: `mca_pml_ucx_send → ucp_proto_rndv_send_start → uct_mm_ep_am_bcopy →
     ucs_x86_nt_buffer_transfer`, SIGSEGV "Invalid permissions".
   - UCX takes the HIP VMM buffer (`hipMemCreate` + `hipMemMap`) for host memory, and copies it
     with the CPU over shared memory.
   - Not known yet: whether VMM memory as such is not recognised, or whether the cause is the
     array spanning two allocations. The first array sent crosses a chunk boundary.

5. **The module `openmpi-rt/ucx`**, loaded by the Open MPI module, sets
   `UCX_TLS=sm,dc_x` and `UCX_NET_DEVICES=mlx5_0:1`.
   - This leaves out the ROCm transports (`rocm_copy`, `rocm_ipc`).
   - It also breaks MPI on MI300A, which has no InfiniBand: "No components were able to be
     opened in the pml framework".
   - `run_mpi_mun.sh` sets `UCX_TLS=self,sm,rocm` and unsets `UCX_NET_DEVICES`.
   - Conclusion 4 holds with both settings.

6. **Between nodes, MPI cannot be tested here:** every partition has a single node, so §2.5 can
   only be tested through IPC within a node.
   - The MI210/MI250 nodes have `mlx5_0` and kernel 6.8, so DMA-BUF is possible.
   - UCX 1.22.0 has no `rocm_gdr`.

>> Why cannot you use MI210 nodes ? there are two of them

7. **`GPU_MEMSET`** (debug mode) uses `hipMemsetD8` + `hipDeviceSynchronize`.
   - `hipDeviceSynchronize` does not wait for OpenMP kernels, which run on HSA queues.
   - This is harmless: target regions without `NOWAIT` are complete when they return.

8. **NVIDIA has not been rebuilt or tested** (no nvfortran or NVIDIA GPU here).
   - Changes to check on ag: `GPU_CREATE`/`GPU_DELETE`, the CMake rework (`-Mpreprocess` kept for
     nvfortran only), and the `#ifdef _OPENACC` in the tests.

## 5. Questions

### Q1. Vendor selection: two modules or one with `#ifdef`? (porting note, §2.2)

| | Two modules (current) | One module, `#ifdef` |
|---|---|---|
| Lines | 815 (398 NVIDIA + 417 AMD) | about 550 (estimate) |
| Duplication | 98 code lines identical in both files; an interface change is made twice | none |
| Readability | plain files, no preprocessor | `#ifdef` in the structures (different `allocFlags`), in each `BIND (C)` name, and in each OpenACC/OpenMP call |

- **Merged sample** (3 routines):
  `/tmp/claude-1596/-home-marguina-fiatallocators/b338935f-d798-4832-ad18-4e863360923c/scratchpad/gpu_helpers_merged_sample.F90`.
  I can move it into the repository if you want to keep it.
- In a merged module, `GPU_VMM_MAP` and the other VMM routines become identical, but
  `GPU_INIT`, `GPU_CREATE`, `GPU_MAP_DATA` and `GPU_MEMSET` keep two branches each.
- My recommendation: keep two modules.

**Answer:**

agreed

### Q2. MPI on `DOUBLESTACK_GPU` arrays: what next?

Possible steps; choose any:

- a. Send one array that stays inside a single chunk, to separate "VMM memory not recognised"
  from "array spanning two allocations".
- b. Read openucx/ucx#12138 and the UCX ROCm code that finds the allocation of a pointer
  (`rocm_copy`/`rocm_ipc` memory domain).
- c. Try the other UCX builds with ROCm on the system (`ucx/1.20.1_rocm7.2.2`, used by module
  `openmpi/rocm-7.2.2/5.0.10`), or a UCX built from source (master, or v1.23.x).
- d. Port `vmm_verbs_check.c` to HIP: register (`ibv_reg_mr`, DMA-BUF) a range spanning two
  `hipMemCreate` allocations, without MPI, on the `mlx5_0` of MI210/MI250.
- e. Leave it for now.

**Answer:**

use the right UCX ; see /home/marguina/bak1/stackdemo


### Q3. HIP graphs

Options:

- a. Keep `test_graph` NVIDIA-only and `test_mpi` without a graph on AMD, as now.
- b. Retry the capture with another compiler: amdflang of ROCm 7.2.2, or AFAR 23.2.1.
- c. Ask AMD whether the OpenMP runtime can launch on a given HIP stream, or whether
  `interop targetsync` will be implemented.

**Answer:**

use gemm kernels, as in stackdemo

### Q4. Test names

`test_acc` now runs OpenACC or OpenMP. Options:

- keep the name;
- rename it, for example to `test_offload`.

The README calls it "OpenACC or OpenMP kernels".

**Answer:**

rename

### Q5. Files outside the AMD helper

These were modified:

- `CMakeLists.txt`, `src/CMakeLists.txt`, `tests/CMakeLists.txt`;
- `gpu_helpers_nvidia.F90` and the peak modules (`GPU_CREATE`, as you chose);
- four tests;
- `README.md`.

Is that acceptable? Should `AMD_PORTING.md` be updated with the results too, or replaced by this
file?

**Answer:**

We will remove this file when porting to AMD is finished

### Q6. Environment

- **fypp** is installed in `~/fypp` (the module Python has pip, but its venv cannot run, because
  of a missing `libpython`). Is that acceptable, or do you prefer another location?
- **Script name:** `env_mun.sh`, after the login node `muncl01`. Is there a better name for this
  system?

**Answer:**

acceptable

### Q7. Commit

- Commit now (on `main`, or on a branch)?
- In one commit, or split (interface change / AMD helper / build / tests / docs)?
- Should someone check NVIDIA on ag first?

**Answer:**

commit in another branch; we will go back to NVIDIA at some point
