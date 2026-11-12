# fiatallocators

Fortran allocators for FIAT-based codes, on CPU and on GPU, behind one abstract interface:

- **double stack**: two LIFO stacks (lower and upper side) in one buffer. On GPU, the buffer is a
  range of device virtual addresses (CUDA VMM), mapped to physical memory on demand: there is no
  sizing, and addresses never change.
- **fixed**: the same double stack in a buffer of fixed size, allocated at once. It reports how
  much of the buffer was actually used.
- **peak**: plain `ALLOCATE`/`DEALLOCATE` of each array. It reports the peak of the memory in use.

Each allocator has a CPU class and a GPU class. The GPU classes run on NVIDIA GPUs (OpenACC, CUDA
driver API) and on AMD GPUs (OpenMP offload, HIP); see [AMD](#amd).

## Classes

| Class | Memory | Sides, order |
|---|---|---|
| `DOUBLESTACK_CPU` | one host buffer of virtual memory (`mmap`, `MAP_NORESERVE`): only the pages touched cost memory | 2 sides, LIFO per side |
| `DOUBLESTACK_GPU` | range of device addresses (CUDA or HIP VMM), physical memory mapped in chunks as each side grows | 2 sides, LIFO per side |
| `FIXED_CPU` | host buffer of `KSIZE` bytes (`ALLOCATE`) | 2 sides, LIFO per side |
| `FIXED_GPU` | device buffer of `KSIZE` bytes (`acc_malloc`, `omp_target_alloc`) | 2 sides, LIFO per side |
| `PEAK_CPU` | one `ALLOCATE` per array | side ignored, any order |
| `PEAK_GPU` | one `ALLOCATE` per array, plus its device copy (`acc_create`; `omp_target_alloc` + `omp_target_associate_ptr`) | side ignored, any order |

All of them extend the abstract class `ALLOCATOR_BASE`.

## Interface

```fortran
USE PARKIND1, ONLY : JPIB, JPRB
USE ALLOCATOR_BASE_MOD, ONLY : ALLOCATOR_BASE, SIDE_LOWER, SIDE_UPPER
USE NEW_ALLOCATOR_MOD, ONLY : NEW_ALLOCATOR

CLASS (ALLOCATOR_BASE), POINTER :: YLALLOC
REAL (KIND=JPRB), POINTER :: ZA (:,:), ZB (:)

CALL NEW_ALLOCATOR (YLALLOC, 'doublestack', LDGPU=.TRUE., KSIZE=0_JPIB)   ! creates and calls INIT

CALL YLALLOC%ALLOCATE (ZA, [NPROMA, NLEV])                ! current side (lower at start)
CALL YLALLOC%ALLOCATE (ZB, [100], LBOUNDS=[0], KSIDE=SIDE_UPPER)
!$ACC PARALLEL LOOP PRESENT (ZA)
...
CALL YLALLOC%DEALLOCATE (ZB)
CALL YLALLOC%DEALLOCATE (ZA)

CALL YLALLOC%DESTROY                                      ! prints the report, releases memory
DEALLOCATE (YLALLOC)
```

### Methods

| Method | Description |
|---|---|
| `INIT (KSIZE [, LDDEBUG] [, LDVERBOSE])` | "Constructor". `KSIZE` is in bytes (`INTEGER (JPIB)`); its meaning per class is given below. `LDDEBUG`: fill freed memory (stack-based classes). `LDVERBOSE`: print every allocation, mapping and release. |
| `ALLOCATE (X, UBOUNDS [, LBOUNDS] [, KSIDE])` | Make the `POINTER` array `X` point to new memory. `UBOUNDS` and `LBOUNDS` are `INTEGER (JPIM)` arrays of size rank; lower bounds default to 1. `KSIDE` (`SIDE_LOWER` or `SIDE_UPPER`) applies to this allocation only. |
| `DEALLOCATE (X)` | Release `X` and nullify it. The side is found from the address. |
| `SET_SIDE (KSIDE)`, `NEXT_SIDE`, `GET_SIDE ()` | The current side, used when `KSIDE` is absent (FIAT style). |
| `REPORT ([KUNIT])` | One line of statistics. |
| `PEAK_USED ()` | Peak of the memory in use, in bytes. For double stacks, this is the peak of lower + upper. |
| `DESTROY` | "Destructor". Prints the report and releases everything. Arrays still allocated are released too, with a warning in verbose mode. |

`X` can be `INTEGER (JPIM)`, `INTEGER (JPIB)`, `REAL (JPRM)`, `REAL (JPRD)` or `LOGICAL (JPLM)`,
of rank 1 to 5. `JPRB` is covered as one of `JPRM`/`JPRD`. Zero-size arrays are allowed.

Fortran has no constructors, and `FINAL` procedures are not called for every variable. Call
`DESTROY` explicitly. Each class also has a `FINAL` procedure that calls `DESTROY` if it was not
called.

### Meaning of `KSIZE`

| Class | `KSIZE` |
|---|---|
| `DOUBLESTACK_CPU` | size of the virtual buffer; 0 = physical memory of the node |
| `DOUBLESTACK_GPU` | size of the reserved range of device addresses; 0 = device memory size. Physical memory is mapped only as the sides grow. |
| `FIXED_*` | size of the buffer, allocated by `INIT` (> 0) |
| `PEAK_*` | ignored |

### Factory

`NEW_ALLOCATOR (YDALLOC, CDKIND, LDGPU, KSIZE [, LDDEBUG] [, LDVERBOSE])`. `CDKIND` is
`'doublestack'`, `'fixed'` or `'peak'`, and `LDGPU` selects the GPU class. The same application code
runs with every allocator.

### Errors

Errors call `ABOR1 (CDTEXT)`, which prints the message and stops with `ERROR STOP 1`. The library
provides its own `ABOR1`, with FIAT's interface, so FIAT's can replace it. Examples:

```
ABOR1: DOUBLESTACK_GPU%DEALLOCATE: LIFO violation: array on the lower side at offset 0 (allocation 1 of 2), but the top of that side is at offset 512; deallocate in reverse order of allocation
ABOR1: FIXED_GPU%ALLOCATE of 2097152 bytes on the lower side: buffer full (lower side 0.0 MiB, upper side 0.0 MiB, free 1.0 MiB, buffer 1.0 MiB)
```

### Reports

`DESTROY` prints one line, for example:

```
DOUBLESTACK_GPU: buffer 97344.0 MiB; peak used: lower 91.6 MiB, upper 152.6 MiB, lower+upper 244.1 MiB; 4 allocations; device memory mapped: lower 128.0 MiB, upper 192.0 MiB, total 320.0 MiB
FIXED_CPU: buffer 256.0 MiB; peak used: lower 10.0 MiB, upper 30.0 MiB, lower+upper 40.0 MiB; 3 allocations
PEAK_CPU: peak memory 40.0 MiB (41943040 bytes); 3 allocations
```

## How it works

### Double stack

```
offset 0                                                                    SIZE
+------------------+---------------------------------------+-----------------+
| lower side  -->  |                 free                  |  <-- upper side |
+------------------+---------------------------------------+-----------------+
```

- **Placement.** Each array starts on a multiple of `ALLOC_ALIGNMENT` bytes (128), and takes a
  multiple of it.
- **LIFO check.** `DEALLOCATE` checks that the array is the top of its side: the current side is
  tried first, then the other one.
- **Full buffer.** When the two sides would collide, `ALLOCATE` aborts.
- **Same addresses.** The same sequence of allocations gives the same addresses at every "time
  step".
- **Shared logic.** `stack_core_mod.F90` holds the logic common to `DOUBLESTACK_*` and `FIXED_*`.

### `DOUBLESTACK_GPU`

- **Reservation.** `INIT` reserves a range of device virtual addresses (`cuMemAddressReserve`),
  which uses no memory.
- **On-demand mapping.** When a side grows past its mapped part, chunks of `VMM_CHUNK` bytes
  (64 MiB) of physical memory are created and mapped (`cuMemCreate`, `cuMemMap`,
  `cuMemSetAccess`). The lower side maps from the start of the range, the upper side from its end.
- **Chunks are kept.** Freed memory stays mapped ("keep" policy): addresses never change, and each
  side keeps its high-water mark mapped. `DESTROY` unmaps everything.
- **Device memory used.** It is the peak of the lower side plus the peak of the upper side, each
  rounded up to the chunk size.
- **Stable addresses.** Device pointers held elsewhere stay valid as the stack grows: CUDA graphs,
  FFT plans, MPI registration caches.
- **GPUDirect RDMA.** Chunks are created with `gpuDirectRDMACapable`, so CUDA-aware MPI can
  transfer them directly.

### GPU arrays, OpenACC and OpenMP

- **Host mirror.** The arrays returned by the GPU stack classes are host pointers into a host
  *mirror* of the device buffer. The mirror is virtual memory, untouched unless the program copies
  data to the host.
- **One mapping.** The whole mirror is declared to the offload runtime once (`acc_map_data` on
  NVIDIA, `omp_target_associate_ptr` on AMD). So every array is present on the device:
  - OpenACC: `PRESENT (X)`, `UPDATE HOST/DEVICE (X)`, `HOST_DATA USE_DEVICE (X)`;
  - OpenMP: `MAP (PRESENT, ALLOC: X)` (or an implicit map), `TARGET UPDATE FROM/TO (X)`,
    `TARGET DATA USE_DEVICE_ADDR (X)`.
- **`PEAK_GPU`.** It creates a device copy of each array (`GPU_CREATE`), with the same effect, and
  keeps its device address to delete it.
- **No directives in the classes.** The library classes call the helper module
  `GPU_HELPERS_MOD` (`gpu_helpers_nvidia.F90` or `gpu_helpers_amd.F90`, same interface). It holds
  every CUDA/HIP and OpenACC/OpenMP call, through `BIND (C)` interfaces.

### Debug mode

With `LDDEBUG=.TRUE.`, the stack-based classes fill freed memory with the byte
`DEBUG_FILL_BYTE` (0xFF): a stale access to a freed `REAL` array reads NaN, and an `INTEGER` reads -1.
On GPU the device memory is filled.

### Tunable parameters

They are in `src/allocator_params_mod.F90`; change them and recompile.

| Parameter | Default | |
|---|---|---|
| `ALLOC_ALIGNMENT` | 128 bytes | alignment of every array (stack-based classes), power of 2 |
| `VMM_CHUNK` | 64 MiB | mapping unit of `DOUBLESTACK_GPU`, multiple of the VMM granularity (2 MiB on NVIDIA, 4 KiB on AMD) |
| `DEBUG_FILL_BYTE` | 255 | fill byte of the debug mode |

## Requirements

- **Compiler.** nvfortran (NVIDIA HPC SDK) or amdflang (AMD; tested: AFAR 24.3.0); CMake ≥ 3.18;
  [fypp](https://github.com/aradi/fypp) generates the type/kind/rank variants.
- **GPU classes, NVIDIA.** OpenACC, and `libcuda` (driver API) and `libcudart` (graph tests).
- **GPU classes, AMD.** OpenMP offload, `libamdhip64` (HIP VMM API); a GPU with VMM support
  (checked at initialisation).
- **MPI test.** A GPU-aware MPI.
- **MPI on `DOUBLESTACK_GPU` arrays that cross chunk boundaries, between nodes.** An array may span
  two physical allocations, so MPI must register the exact range:
  - registration of GPU memory through DMA-BUF: NVIDIA open GPU kernel modules, Linux ≥ 5.12,
    recent OFED;
  - UCX ≥ 1.23 with [openucx/ucx#12186](https://github.com/openucx/ucx/pull/12186) (#12188 on the
    `v1.23.x` branch).

  Older UCX releases register only the first allocation, and the transfer fails. With registration
  through `nvidia_peermem`, the registration itself fails. `FIXED_GPU` and `PEAK_GPU` arrays live in
  one allocation and work with any CUDA-aware MPI.

## Build

NVIDIA:

```sh
source scripts/env_ag.sh       # ECMWF ag (GH200): NVHPC 26.1, HPC-X, CMake, fypp; adapt elsewhere
cmake -S . -B build_gpu -DCMAKE_Fortran_COMPILER=nvfortran \
      -DENABLE_GPU=ON -DENABLE_MPI=ON -DGPU_CC=cc90
cmake --build build_gpu -j 8
```

AMD:

```sh
source scripts/env_mun.sh      # AMD cluster: AFAR 24.3.0, its Open MPI, CMake, fypp; adapt elsewhere
cmake -S . -B build_amd -DCMAKE_Fortran_COMPILER=amdflang -DCMAKE_C_COMPILER=amdclang \
      -DENABLE_GPU=ON -DENABLE_MPI=ON -DGPU_ARCH=gfx90a
cmake --build build_amd -j 16
```

| CMake option | Default | |
|---|---|---|
| `ENABLE_GPU` | `OFF` | build the GPU classes (otherwise CPU only, no offload flags) |
| `ENABLE_MPI` | `OFF` | build the MPI test |
| `GPU_VENDOR` | from the compiler | helper set (`src/gpu_helpers_<vendor>.F90`): `nvidia` (nvfortran) or `amd` (amdflang) |
| `GPU_CC` | `cc90` | NVIDIA, `-gpu=` target: `cc80` for A100, `cc90` for GH200 |
| `GPU_ARCH` | `gfx90a` | AMD, `--offload-arch=` target: `gfx90a` for MI210/MI250, `gfx942` for MI300A/MI300X; `gfx90a,gfx942` for both |

Link applications with the `fiatallocators` library. Its modules are in `<build>/modules`.

## Tests

Each test program takes `<doublestack|fixed|peak> <cpu|gpu>` and runs the same code for every
allocator, through `NEW_ALLOCATOR`.

| Test | Allocators | Checks |
|---|---|---|
| `test_types` | all | every type/kind/rank, bounds, a zero-size array; values written and read back, through the device on GPU |
| `test_sides` | all | `SET_SIDE`/`NEXT_SIDE`/`KSIDE`; sides grow in opposite directions; interleaved frees; memory reused |
| `test_lifo_violation` | doublestack, fixed | a LIFO violation aborts (expected failure) |
| `test_addresses` | doublestack, fixed | same sequence, same addresses, at every step |
| `test_debug` | doublestack, fixed | freed memory reads NaN in debug mode |
| `test_peak` | all | `PEAK_USED` is 40 MiB for a known sequence |
| `test_fixed_full` | fixed | a full buffer aborts (expected failure) |
| `test_offload` (GPU) | all | OpenACC or OpenMP kernels on arrays crossing chunks, both sides; `HOST_DATA USE_DEVICE` / `USE_DEVICE_ADDR` |
| `test_graph` (GPU) | all | `A = A + 1`, `B = B + 1` captured once into a graph (NVIDIA: OpenACC kernels, CUDA graph; AMD: hipBLAS SGEMMs, HIP graph), nothing run during the capture, replayed before and after the allocator grows (peak: only while the arrays stay allocated, since they may move) |
| `hip_vmm_layout` (GPU, AMD) | | the `BIND (C)` copies of the HIP structures and constants match the ROCm headers |
| `test_mpi` | all | 2 ranks: graph replays and `MPI_Sendrecv` of arrays crossing chunks (lower and upper side), before and after growth |

The GPU tests hold both sets of directives: OpenACC under `#ifdef _OPENACC`, OpenMP otherwise.

Run the single-process tests (CPU, and GPU when built with it) with:

```sh
cd build_gpu && ctest
```

Run the MPI test on two nodes with one GPU each, on ag:

```sh
sbatch scripts/run_mpi_ag.sh          # output: test_mpi_<jobid>.out
```

The script loads UCX `v1.23.x` (`/perm/sor/install/ucx-test/aarch64/ucx-v1.23.x`) with
`LD_PRELOAD`, in place of the UCX of HPC-X. It also runs `mpirun --bind-to none`, which ag needs.

On the AMD cluster (one node per partition, so both ranks share a node):

```sh
sbatch [-p MI250|MI300A|MI300X] scripts/run_ctest_mun.sh build_amd   # ctest on one GPU
sbatch [-p MI250|MI300A|MI300X] scripts/run_mpi_mun.sh build_amd     # test_mpi, 2 GPUs
```

## Files

| File | Contents |
|---|---|
| `src/allocator_base_mod.fypp` | `ALLOCATOR_BASE`: deferred interfaces, typed `ALLOCATE`/`DEALLOCATE` |
| `src/stack_core_mod.F90` | two-sided LIFO bookkeeping (double stacks and fixed) |
| `src/peak_core_mod.F90` | bookkeeping of the peak classes |
| `src/doublestack_cpu_mod.F90`, `src/doublestack_gpu_mod.F90` | double stacks |
| `src/fixed_cpu_mod.F90`, `src/fixed_gpu_mod.F90` | fixed buffers |
| `src/peak_cpu_mod.F90`, `src/peak_gpu_mod.F90` | peak allocators |
| `src/new_allocator_mod.F90` | factory |
| `src/gpu_helpers_nvidia.F90` | NVIDIA helpers: CUDA driver VMM API, OpenACC runtime |
| `src/gpu_helpers_amd.F90` | AMD helpers: HIP VMM API, OpenMP offload runtime |
| `src/host_helpers_mod.F90` | libc helpers: `mmap`, `munmap`, `sysconf`, `memset` |
| `src/allocator_params_mod.F90` | tunable parameters, side constants |
| `src/abor1.F90`, `src/abor1.intfb.h` | `ABOR1` |
| `src/parkind1.F90` | copy of FIAT's `PARKIND1` |
| `tests/` | tests; `cuda_graph_mod.F90`, `hip_graph_mod.F90`: CUDA and HIP graph helpers for the tests; `c/hip_vmm_layout.c`: HIP layout check |
| `scripts/env_ag.sh`, `scripts/run_mpi_ag.sh` | environment and MPI job for ECMWF ag |
| `scripts/env_mun.sh`, `scripts/run_ctest_mun.sh`, `scripts/run_mpi_mun.sh` | environment, ctest and MPI jobs for the AMD cluster |

## AMD

The AMD version is `src/gpu_helpers_amd.F90`: a module with the same name and public routines as
the NVIDIA one, selected by `GPU_VENDOR`. It uses the HIP VMM API, and OpenMP in place of OpenACC
(`omp_target_associate_ptr` in place of `acc_map_data`, `omp_target_alloc` in place of
`acc_malloc`). `GPU_CREATE` returns the device address of the copy, and `GPU_DELETE` takes it,
since OpenMP has no `acc_create`/`acc_delete`.

Status (AFAR 24.3.0 with its HIP and hipBLAS, Open MPI 5.0.11, UCX with HIP VMM support, see
below):

| | MI210 | MI250 | MI300A | MI300X |
|---|---|---|---|---|
| ctest (39 tests, CPU and GPU) | passed | passed | passed | passed |
| `test_mpi`, CPU and GPU, all allocators | passed | passed | passed | passed |

`test_mpi` runs on one node (each partition has one): GPU to GPU through UCX `rocm_ipc`. Between
nodes (RDMA registration of a range spanning two physical allocations) is not tested.

Notes:

- **Graphs hold hipBLAS calls.** The OpenMP runtime launches kernels on HSA queues, not HIP
  streams: a HIP stream capture records none of them (0 nodes), and
  `!$omp interop init (targetsync: ...)` returns `omp_interop_none`. hipBLAS calls on a HIP stream
  can be captured, as in ecTrans: on AMD, `test_graph` and `test_mpi` capture `X = X + 1` as an
  SGEMM, `X (M, N) += U (M, K) * V (K, N)` with `U (:, 1) = 1`, `U (:, 2:) = 0`, `V = 1`
  (`tests/hip_graph_mod.F90`).
- **UCX.** UCX 1.22.0 (the Open MPI module) takes HIP VMM memory (`hipMemCreate` + `hipMemMap`)
  for host memory, and segfaults in `uct_mm_ep_am_bcopy` → `ucs_x86_nt_buffer_transfer` on
  `DOUBLESTACK_GPU` arrays. `scripts/run_mpi_mun.sh` preloads a UCX built from master `72895c480`
  plus the draft ROCm VMM pull requests
  [#12137](https://github.com/openucx/ucx/pull/12137) (memory-type detection of VMM memory),
  [#12138](https://github.com/openucx/ucx/pull/12138) (no CPU copy of VMM memory),
  [#12139](https://github.com/openucx/ucx/pull/12139) (UCM hooks on VMM map/unmap) and
  [#12140](https://github.com/openucx/ucx/pull/12140) (`rocm_ipc` of VMM memory through dma-buf),
  in `/home/marguina/bak1/ucx-vmm/install` (built for stackdemo). `FIXED_GPU` and `PEAK_GPU`
  arrays work with either UCX.

  Exact version: UCX 1.24.0 (development), source `/home/marguina/bak1/ucx-vmm/src`, branch
  `vmm-series` at `ff2fb9655`, which is:

  | Commit | Contents |
  |---|---|
  | `72895c480` | base: openucx/ucx master (merge of #12106) |
  | `12d45f12e` | #12137: UCT/ROCM: Treat `HSA_EXT_POINTER_TYPE_HSA_VMEM` as ROCm memory |
  | `b6839ad93` | #12138: UCT/ROCM/COPY: Do not access VMM device memory with the CPU |
  | `8be6ca613` | #12139: UCM/ROCM: Hook the HSA virtual memory map and unmap calls |
  | `0204c61b4` | #12140: UCT/ROCM/IPC: Share VMM memory through dma-buf file descriptors |
  | `d70921490`, `ff2fb9655` | merges of the four branches |

  The four PRs are drafts; merged on their common base `72895c480`, as on current master #12139
  conflicts. Configure options: those of UCX 1.22.0 (`ucx_info -b`). It was built with prefix
  `/home/marguina/ucx-vmm/install` and moved since (its `.pc` files still give that prefix);
  preloading the libraries by path works.
- **`UCX_TLS`.** The Open MPI module loads `openmpi-rt/ucx`, which sets `UCX_TLS=sm,dc_x` (no ROCm
  transport) and `UCX_NET_DEVICES=mlx5_0:1` (fails on MI300A, which has no InfiniBand).
  `run_mpi_mun.sh` sets `UCX_TLS=self,sm,rocm`.
- **`GPU_MEMSET`** (debug mode) synchronises HIP only: OpenMP target regions without `NOWAIT` are
  complete when they return.
