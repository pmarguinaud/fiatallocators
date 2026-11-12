PROGRAM TEST_SIDES

! Test b: the two sides, selected with SET_SIDE / NEXT_SIDE or with KSIDE (one allocation only).
! Double stacks and fixed: the lower side grows up, the upper side grows down, above the lower one.
! Arrays are freed in an order that is LIFO per side but interleaved between the sides.
! Peak: the side is ignored; the same calls must work.

USE ISO_C_BINDING
USE PARKIND1, ONLY : JPIM, JPRD
USE ALLOCATOR_BASE_MOD, ONLY : ALLOCATOR_BASE, SIDE_LOWER, SIDE_UPPER
USE TEST_UTIL_MOD, ONLY : TEST_SETUP, CHECK, TEST_END

IMPLICIT NONE

CLASS (ALLOCATOR_BASE), POINTER :: YLALLOC
CHARACTER (LEN=16) :: CLKIND
LOGICAL :: LLGPU, LLSTACK
REAL (KIND=JPRD), POINTER :: A1 (:), A2 (:), B1 (:), B2 (:), C1 (:)
INTEGER (KIND=C_INTPTR_T) :: IA1, IA2, IB1, IB2, IC1

CALL TEST_SETUP ('test_sides', YLALLOC, CLKIND, LLGPU)
LLSTACK = CLKIND /= 'peak'

CALL CHECK (YLALLOC%GET_SIDE () == SIDE_LOWER, 'initial side is the lower side')
CALL YLALLOC%ALLOCATE (A1, [1000])                        ! lower (current side)
CALL YLALLOC%ALLOCATE (B1, [2000], KSIDE=SIDE_UPPER)      ! upper, this allocation only
CALL CHECK (YLALLOC%GET_SIDE () == SIDE_LOWER, 'KSIDE does not change the current side')
CALL YLALLOC%SET_SIDE (SIDE_UPPER)
CALL YLALLOC%ALLOCATE (B2, [3000])                        ! upper
CALL YLALLOC%NEXT_SIDE
CALL CHECK (YLALLOC%GET_SIDE () == SIDE_LOWER, 'NEXT_SIDE')
CALL YLALLOC%ALLOCATE (A2, [4000])                        ! lower
CALL YLALLOC%ALLOCATE (C1, [10], KSIDE=SIDE_UPPER)        ! upper

IA1 = ADDR (A1); IA2 = ADDR (A2); IB1 = ADDR (B1); IB2 = ADDR (B2); IC1 = ADDR (C1)
IF (LLSTACK) THEN
  CALL CHECK (IA2 >= IA1 + 8 * 1000, 'lower side grows up')
  CALL CHECK (IB2 + 8 * 3000 <= IB1 .AND. IC1 + 8 * 10 <= IB2, 'upper side grows down')
  CALL CHECK (IC1 >= IA2 + 8 * 4000, 'upper side above the lower side')
ENDIF

A1 = 1; A2 = 2; B1 = 3; B2 = 4; C1 = 5
CALL CHECK (ALL (A1 == 1) .AND. ALL (A2 == 2) .AND. ALL (B1 == 3) .AND. ALL (B2 == 4) .AND. ALL (C1 == 5), &
          & 'arrays do not overlap')

! Interleaved, LIFO per side; the current side is the lower one
CALL YLALLOC%DEALLOCATE (C1)
CALL YLALLOC%DEALLOCATE (A2)
CALL YLALLOC%DEALLOCATE (B2)
CALL YLALLOC%DEALLOCATE (A1)
CALL YLALLOC%DEALLOCATE (B1)

! The memory is reused: the same allocations give the same addresses
IF (LLSTACK) THEN
  CALL YLALLOC%ALLOCATE (A1, [1000])
  CALL YLALLOC%ALLOCATE (B1, [2000], KSIDE=SIDE_UPPER)
  CALL CHECK (ADDR (A1) == IA1 .AND. ADDR (B1) == IB1, 'memory reused after DEALLOCATE')
  CALL YLALLOC%DEALLOCATE (B1)
  CALL YLALLOC%DEALLOCATE (A1)
ENDIF

CALL TEST_END (YLALLOC)

CONTAINS

FUNCTION ADDR (P) RESULT (KADDR)
REAL (KIND=JPRD), POINTER, INTENT (IN) :: P (:)
INTEGER (KIND=C_INTPTR_T) :: KADDR
KADDR = TRANSFER (C_LOC (P), KADDR)
END FUNCTION ADDR

END PROGRAM TEST_SIDES
