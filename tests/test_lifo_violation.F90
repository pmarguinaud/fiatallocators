PROGRAM TEST_LIFO_VIOLATION

! Test b: freeing an array that is not the top of its side must abort with a clear message.
! Expected to FAIL (ABOR1); registered with WILL_FAIL for the double stacks and fixed allocators.

USE PARKIND1, ONLY : JPRM
USE ALLOCATOR_BASE_MOD, ONLY : ALLOCATOR_BASE
USE TEST_UTIL_MOD, ONLY : TEST_SETUP, TEST_END

IMPLICIT NONE

CLASS (ALLOCATOR_BASE), POINTER :: YLALLOC
CHARACTER (LEN=16) :: CLKIND
LOGICAL :: LLGPU
REAL (KIND=JPRM), POINTER :: A1 (:), A2 (:)

CALL TEST_SETUP ('test_lifo_violation', YLALLOC, CLKIND, LLGPU)
CALL YLALLOC%ALLOCATE (A1, [100])
CALL YLALLOC%ALLOCATE (A2, [100])
CALL YLALLOC%DEALLOCATE (A1)          ! A2 is the top: LIFO violation
PRINT '(A)', 'no abort: LIFO violation not detected'
CALL TEST_END (YLALLOC)

END PROGRAM TEST_LIFO_VIOLATION
