PROGRAM TEST_GRAPH

! Test e (GPU): OpenACC kernels on arrays of the allocator are captured once into a CUDA graph,
! then replayed. A is on the lower side, B on the upper side; B crosses a chunk boundary
! (DOUBLESTACK_GPU).
! Double stacks and fixed: the allocator then grows (more arrays on both sides, new chunks mapped
! for DOUBLESTACK_GPU) and the same graph is replayed again: A and B have not moved.
! Peak: arrays may move when freed and allocated again, so the graph is only replayed while A and
! B stay allocated (no growth part).

USE PARKIND1, ONLY : JPIM, JPRM
USE ALLOCATOR_BASE_MOD, ONLY : ALLOCATOR_BASE, SIDE_LOWER, SIDE_UPPER
USE TEST_UTIL_MOD, ONLY : TEST_SETUP, CHECK, TEST_END
USE CUDA_GRAPH_MOD, ONLY : GRAPH_BEGIN, GRAPH_END, GRAPH_LAUNCH, GRAPH_SYNC, GRAPH_DESTROY

IMPLICIT NONE

CLASS (ALLOCATOR_BASE), POINTER :: YLALLOC
CHARACTER (LEN=16) :: CLKIND
LOGICAL :: LLGPU
INTEGER, PARAMETER :: IQ = 1                                   ! OpenACC queue captured
INTEGER (KIND=JPIM), PARAMETER :: NA = 4000000                 ! A: 15 MiB, lower side
INTEGER (KIND=JPIM), PARAMETER :: NB = 20000000                ! B: 76 MiB, upper side
INTEGER (KIND=JPIM), PARAMETER :: NG = 20000000                ! growth: 76 MiB on each side
REAL (KIND=JPRM), POINTER :: A (:), B (:), G1 (:), G2 (:)
INTEGER :: INODES, IREP, NREP
INTEGER (KIND=JPIM) :: J

CALL TEST_SETUP ('test_graph', YLALLOC, CLKIND, LLGPU)
IF (.NOT. LLGPU) CALL CHECK (.FALSE., 'test_graph is a GPU test')

CALL YLALLOC%ALLOCATE (A, [NA])
CALL YLALLOC%ALLOCATE (B, [NB], KSIDE=SIDE_UPPER)
!$ACC PARALLEL LOOP PRESENT (A, B)
DO J = 1, NB
  IF (J <= NA) A (J) = 0.
  B (J) = REAL (MOD (J, 1000))
ENDDO

! Capture: A = A + 1, B = B + 1, on queue IQ
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
PRINT '(A,I0,A)', 'graph captured: ', INODES, ' node(s)'

NREP = 0
DO IREP = 1, 2
  CALL GRAPH_LAUNCH
  NREP = NREP + 1
ENDDO
CALL GRAPH_SYNC
CALL CHECK_AB ('after 2 replays')

IF (CLKIND /= 'peak') THEN
  CALL YLALLOC%ALLOCATE (G1, [NG])
  CALL YLALLOC%ALLOCATE (G2, [NG], KSIDE=SIDE_UPPER)
  !$ACC PARALLEL LOOP PRESENT (G1, G2)
  DO J = 1, NG
    G1 (J) = -1.
    G2 (J) = -2.
  ENDDO
  DO IREP = 1, 3
    CALL GRAPH_LAUNCH
    NREP = NREP + 1
  ENDDO
  CALL GRAPH_SYNC
  CALL CHECK_AB ('after the allocator grew, 5 replays')
  !$ACC UPDATE HOST (G1 (1:1), G2 (NG:NG))
  CALL CHECK (G1 (1) == -1. .AND. G2 (NG) == -2., 'growth arrays untouched by the graph')
  CALL YLALLOC%DEALLOCATE (G2)
  CALL YLALLOC%DEALLOCATE (G1)
ENDIF

CALL GRAPH_DESTROY
CALL YLALLOC%DEALLOCATE (B)
CALL YLALLOC%DEALLOCATE (A)
CALL TEST_END (YLALLOC)

CONTAINS

SUBROUTINE CHECK_AB (CDWHEN)

CHARACTER (LEN=*), INTENT (IN) :: CDWHEN

INTEGER (KIND=JPIM) :: IBAD

!$ACC UPDATE HOST (A, B)
CALL CHECK (ALL (A == REAL (NREP)), 'A '//CDWHEN)
IBAD = 0
DO J = 1, NB
  IF (B (J) /= REAL (MOD (J, 1000) + NREP)) IBAD = IBAD + 1
ENDDO
CALL CHECK (IBAD == 0, 'B '//CDWHEN)
PRINT '(A,A,A,I0)', 'checked ', CDWHEN, ': replays ', NREP

END SUBROUTINE CHECK_AB

END PROGRAM TEST_GRAPH
