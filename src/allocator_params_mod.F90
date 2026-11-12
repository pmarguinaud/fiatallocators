MODULE ALLOCATOR_PARAMS_MOD

! Tunable parameters of the allocators. Change them here and recompile.

USE PARKIND1, ONLY : JPIM, JPIB

IMPLICIT NONE

! Every array starts on a multiple of ALLOC_ALIGNMENT bytes (power of 2) on the stack-based
! allocators (DOUBLESTACK_*, FIXED_*), and takes a multiple of ALLOC_ALIGNMENT bytes.
INTEGER (KIND=JPIB), PARAMETER :: ALLOC_ALIGNMENT = 128

! DOUBLESTACK_GPU maps physical memory VMM_CHUNK bytes at a time, on each side. Must be a multiple
! of the VMM allocation granularity of the GPU (2 MiB on A100 and GH200).
INTEGER (KIND=JPIB), PARAMETER :: VMM_CHUNK = 64_JPIB * 1024_JPIB * 1024_JPIB

! Debug mode: freed memory is filled with this byte. 255 (0xFF) makes every REAL a NaN and every
! INTEGER -1.
INTEGER (KIND=JPIM), PARAMETER :: DEBUG_FILL_BYTE = 255

! The two sides of a double stack
INTEGER (KIND=JPIM), PARAMETER :: SIDE_LOWER = 0   ! grows up from the start of the buffer
INTEGER (KIND=JPIM), PARAMETER :: SIDE_UPPER = 1   ! grows down from the end of the buffer

END MODULE ALLOCATOR_PARAMS_MOD
