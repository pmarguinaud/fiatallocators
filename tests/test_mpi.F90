PROGRAM TEST_MPI

! Test f (MPI, 2 ranks, one GPU each): as stackdemo, with every allocator.
!   1. A, B on the lower side, R on the upper side. With DOUBLESTACK_GPU, B and R cross chunk
!      boundaries (each spans two physical allocations).
!   2. GPU: A = A + 1, B = B + 1 captured once into a graph, replayed twice. NVIDIA: two OpenACC
!      kernels in a CUDA graph. AMD: two hipBLAS SGEMMs in a HIP graph (HIP_GRAPH_MOD; OpenMP
!      target regions cannot be captured). CPU: the same updates on the host.
!   3. Each rank sends B to the other one, which receives it in R (GPU: device addresses,
!      HOST_DATA USE_DEVICE or USE_DEVICE_ADDR, GPU-aware MPI). Values checked.
!   4. The allocator grows: G (lower), then R2 (upper, crossing another boundary). Not for 'peak'.
!   5. Graph replayed 3 more times, B exchanged into R2, values checked.
! Usage: mpirun -n 2 test_mpi <doublestack|fixed|peak> <cpu|gpu>

#ifdef _OPENACC
USE OPENACC
#elif defined(_OPENMP)
USE OMP_LIB
#endif
USE PARKIND1, ONLY : JPIM, JPIB, JPRM
USE ALLOCATOR_BASE_MOD, ONLY : ALLOCATOR_BASE, SIDE_LOWER, SIDE_UPPER
USE TEST_UTIL_MOD, ONLY : TEST_SETUP, CHECK, TEST_END, NFAIL
#if defined(WITH_GPU) && defined(_OPENACC)
USE CUDA_GRAPH_MOD, ONLY : GRAPH_BEGIN, GRAPH_END, GRAPH_LAUNCH, GRAPH_SYNC, GRAPH_DESTROY
#elif defined(WITH_GPU)
USE HIP_GRAPH_MOD, ONLY : GRAPH_BEGIN, GRAPH_ADD_ONE, GRAPH_END, GRAPH_LAUNCH, GRAPH_SYNC, &
                        & GRAPH_DESTROY, GRAPH_ONES, GEMM_M, GEMM_K
#endif

IMPLICIT NONE

! mpif.h rather than USE MPI: the HPC-X of NVHPC on aarch64 ships a gfortran mpi.mod
INCLUDE 'mpif.h'

CLASS (ALLOCATOR_BASE), POINTER :: YLALLOC
CHARACTER (LEN=16) :: CLKIND
CHARACTER (LEN=16) :: CLLOCAL
LOGICAL :: LLGPU
INTEGER, PARAMETER :: IQ = 1
INTEGER (KIND=JPIM), PARAMETER :: NA = 4000000                 ! 15 MiB
INTEGER (KIND=JPIM), PARAMETER :: NB = 20000000                ! 76 MiB: B, R, G, R2
REAL (KIND=JPRM), POINTER :: A (:), B (:), R (:), G (:), R2 (:)
REAL (KIND=JPRM), POINTER :: U (:,:), V (:,:)                  ! SGEMM operands (AMD)
INTEGER :: IRANK, ISIZE, IPEER, ILOCAL, IERR, INODES, IREP, NREP, NBADALL
INTEGER (KIND=JPIM) :: J

CALL MPI_INIT (IERR)
CALL MPI_COMM_RANK (MPI_COMM_WORLD, IRANK, IERR)
CALL MPI_COMM_SIZE (MPI_COMM_WORLD, ISIZE, IERR)
IF (ISIZE /= 2) CALL MPI_ABORT (MPI_COMM_WORLD, 1, IERR)
IPEER = 1 - IRANK

! One GPU per rank, before the allocator initialises the device
CALL GET_ENVIRONMENT_VARIABLE ('OMPI_COMM_WORLD_LOCAL_RANK', CLLOCAL)
ILOCAL = 0
IF (CLLOCAL /= '') READ (CLLOCAL, *) ILOCAL
#if defined(WITH_GPU) && defined(_OPENACC)
CALL ACC_SET_DEVICE_NUM (MOD (ILOCAL, ACC_GET_NUM_DEVICES (ACC_DEVICE_NVIDIA)), ACC_DEVICE_NVIDIA)
#elif defined(WITH_GPU) && defined(_OPENMP)
CALL OMP_SET_DEFAULT_DEVICE (MOD (ILOCAL, OMP_GET_NUM_DEVICES ()))
#endif

CALL TEST_SETUP ('test_mpi', YLALLOC, CLKIND, LLGPU, KSIZE=512_JPIB * 1024_JPIB * 1024_JPIB, &
               & LDVERBOSE=IRANK == 0)

CALL SAY ('=== 1. allocate A, B (lower), R (upper)')
CALL YLALLOC%ALLOCATE (A, [NA])
CALL YLALLOC%ALLOCATE (B, [NB])
CALL YLALLOC%ALLOCATE (R, [NB], KSIDE=SIDE_UPPER)
A = 0.
DO J = 1, NB
  B (J) = REAL (MOD (J, 1000) + 1000 * IRANK)
ENDDO
IF (LLGPU) THEN
#ifdef _OPENACC
  !$ACC UPDATE DEVICE (A, B)
#else
  !$OMP TARGET UPDATE TO (A, B)
#endif
ENDIF

CALL SAY ('=== 2. capture A = A + 1, B = B + 1; replay twice')
#if defined(WITH_GPU) && defined(_OPENACC)
IF (LLGPU) THEN
  CALL GRAPH_BEGIN (IQ)
  !$ACC PARALLEL LOOP PRESENT (A) ASYNC (IQ)
  DO J = 1, NA
    A (J) = A (J) + 1.
  ENDDO
  !$ACC PARALLEL LOOP PRESENT (B) ASYNC (IQ)
  DO J = 1, NB
    B (J) = B (J) + 1.
  ENDDO
  CALL GRAPH_END (INODES)
  CALL CHECK (INODES == 2, 'graph of 2 kernels')
ENDIF
#elif defined(WITH_GPU)
IF (LLGPU) THEN
  CALL YLALLOC%ALLOCATE (U, [GEMM_M, GEMM_K])
  CALL YLALLOC%ALLOCATE (V, [GEMM_K, NB / GEMM_M])
  CALL GRAPH_ONES (U, V)
  CALL GRAPH_BEGIN
  CALL GRAPH_ADD_ONE (A, U, V)
  CALL GRAPH_ADD_ONE (B, U, V)
  CALL GRAPH_END (INODES)
  CALL CHECK (INODES == 2, 'graph of 2 SGEMMs')
ENDIF
#endif
NREP = 0
CALL REPLAY (2)

CALL SAY ('=== 3. exchange B into R')
CALL EXCHANGE (B, R, NB)
CALL CHECK_RESULT ('after 2 replays', R)

IF (CLKIND /= 'peak') THEN
  CALL SAY ('=== 4. grow: G (lower), R2 (upper)')
  CALL YLALLOC%ALLOCATE (G, [NB])
  CALL YLALLOC%ALLOCATE (R2, [NB], KSIDE=SIDE_UPPER)
  CALL SAY ('=== 5. replay 3 more times, exchange B into R2')
  CALL REPLAY (3)
  CALL EXCHANGE (B, R2, NB)
  CALL CHECK_RESULT ('after the allocator grew, 5 replays', R2)
  CALL YLALLOC%DEALLOCATE (R2)
  CALL YLALLOC%DEALLOCATE (G)
ENDIF

#ifdef WITH_GPU
IF (LLGPU) CALL GRAPH_DESTROY
#ifndef _OPENACC
IF (LLGPU) CALL YLALLOC%DEALLOCATE (V)
IF (LLGPU) CALL YLALLOC%DEALLOCATE (U)
#endif
#endif
CALL YLALLOC%DEALLOCATE (R)
CALL YLALLOC%DEALLOCATE (B)
CALL YLALLOC%DEALLOCATE (A)
CALL MPI_ALLREDUCE (NFAIL, NBADALL, 1, MPI_INTEGER, MPI_SUM, MPI_COMM_WORLD, IERR)
IF (IRANK == 0) PRINT '(A,A)', 'ALL RANKS: ', MERGE ('OK   ', 'WRONG', NBADALL == 0)
CALL TEST_END (YLALLOC)
CALL MPI_FINALIZE (IERR)

CONTAINS

SUBROUTINE REPLAY (KN)

INTEGER, INTENT (IN) :: KN

INTEGER :: JREP

DO JREP = 1, KN
  IF (LLGPU) THEN
#ifdef WITH_GPU
    CALL GRAPH_LAUNCH
#endif
  ELSE
    A = A + 1.
    B = B + 1.
  ENDIF
  NREP = NREP + 1
ENDDO
#ifdef WITH_GPU
IF (LLGPU) CALL GRAPH_SYNC
#endif

END SUBROUTINE REPLAY

SUBROUTINE EXCHANGE (S, RR, N)

! Send S to the peer, receive its S in RR (device addresses on GPU)

INTEGER (KIND=JPIM), INTENT (IN) :: N
REAL (KIND=JPRM) :: S (N), RR (N)

IF (LLGPU) THEN
#ifdef _OPENACC
  !$ACC HOST_DATA USE_DEVICE (S, RR)
  CALL MPI_SENDRECV (S, N, MPI_REAL, IPEER, 1, RR, N, MPI_REAL, IPEER, 1, MPI_COMM_WORLD, &
                   & MPI_STATUS_IGNORE, IERR)
  !$ACC END HOST_DATA
#else
  !$OMP TARGET DATA USE_DEVICE_ADDR (S, RR)
  CALL MPI_SENDRECV (S, N, MPI_REAL, IPEER, 1, RR, N, MPI_REAL, IPEER, 1, MPI_COMM_WORLD, &
                   & MPI_STATUS_IGNORE, IERR)
  !$OMP END TARGET DATA
#endif
ELSE
  CALL MPI_SENDRECV (S, N, MPI_REAL, IPEER, 1, RR, N, MPI_REAL, IPEER, 1, MPI_COMM_WORLD, &
                   & MPI_STATUS_IGNORE, IERR)
ENDIF

END SUBROUTINE EXCHANGE

SUBROUTINE CHECK_RESULT (CDWHEN, RR)

! A = NREP; RR = the peer's B = MOD (J, 1000) + 1000 * IPEER + NREP

CHARACTER (LEN=*), INTENT (IN) :: CDWHEN
REAL (KIND=JPRM), POINTER, INTENT (IN) :: RR (:)

INTEGER (KIND=JPIM) :: IBAD

IF (LLGPU) THEN
#ifdef _OPENACC
  !$ACC UPDATE HOST (A, RR)
#else
  !$OMP TARGET UPDATE FROM (A, RR)
#endif
ENDIF
CALL CHECK (ALL (A == REAL (NREP)), 'A '//CDWHEN)
IBAD = 0
DO J = 1, NB
  IF (RR (J) /= REAL (MOD (J, 1000) + 1000 * IPEER + NREP)) IBAD = IBAD + 1
ENDDO
CALL CHECK (IBAD == 0, 'received buffer '//CDWHEN)
IF (IRANK == 0) PRINT '(A,A,A,I0,A)', 'CHECK ', CDWHEN, ': rank 0, ', IBAD, ' wrong value(s) received'

END SUBROUTINE CHECK_RESULT

SUBROUTINE SAY (CD)

CHARACTER (LEN=*), INTENT (IN) :: CD

IF (IRANK == 0) PRINT '(A)', CD

END SUBROUTINE SAY

END PROGRAM TEST_MPI
