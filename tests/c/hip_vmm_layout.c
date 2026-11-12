/* Checks the HIP VMM structures and constants copied (BIND (C)) in src/gpu_helpers_amd.F90
   against the ROCm headers: sizes, field offsets and enum values. Prints them, and fails if one
   differs from the value used in the Fortran module. */
#define __HIP_PLATFORM_AMD__
#include <stdio.h>
#include <stddef.h>
#include <hip/hip_runtime_api.h>

static int nfail = 0;

static void check (const char *what, long value, long expected)
{
  printf ("%-58s %6ld %s\n", what, value, value == expected ? "ok" : "WRONG");
  if (value != expected) {
    printf ("  expected by gpu_helpers_amd.F90: %ld\n", expected);
    nfail++;
  }
}

#define SIZE(T, E)       check ("sizeof (" #T ")", (long) sizeof (T), E)
#define OFF(T, F, E)     check ("offsetof (" #T ", " #F ")", (long) offsetof (T, F), E)
#define FSIZE(T, F, E)   check ("sizeof (" #T "." #F ")", (long) sizeof (((T *)0)->F), E)
#define VAL(V, E)        check (#V, (long) V, E)

int main (void)
{
  /* TYPE HIPMEMLOCATION: 2 x C_INT */
  SIZE (hipMemLocation, 8);
  OFF (hipMemLocation, type, 0);
  OFF (hipMemLocation, id, 4);
  /* TYPE HIPMEMALLOCATIONPROP: C_INT, C_INT, HIPMEMLOCATION, C_PTR, C_SIGNED_CHAR x 2, C_SHORT */
  SIZE (hipMemAllocationProp, 32);
  OFF (hipMemAllocationProp, type, 0);
  OFF (hipMemAllocationProp, requestedHandleType, 4);
  OFF (hipMemAllocationProp, location, 8);
  OFF (hipMemAllocationProp, win32HandleMetaData, 16);
  OFF (hipMemAllocationProp, allocFlags.compressionType, 24);
  OFF (hipMemAllocationProp, allocFlags.gpuDirectRDMACapable, 25);
  OFF (hipMemAllocationProp, allocFlags.usage, 26);
  FSIZE (hipMemAllocationProp, allocFlags.usage, 2);
  /* TYPE HIPMEMACCESSDESC: HIPMEMLOCATION, C_INT */
  SIZE (hipMemAccessDesc, 12);
  OFF (hipMemAccessDesc, location, 0);
  OFF (hipMemAccessDesc, flags, 8);
  /* Handles are passed as C_INTPTR_T */
  SIZE (hipMemGenericAllocationHandle_t, 8);
  /* Enum values (PARAMETERs of the module) */
  VAL (hipMemAllocationTypePinned, 1);
  VAL (hipMemLocationTypeDevice, 1);
  VAL (hipMemAccessFlagsProtReadWrite, 3);
  VAL (hipMemAllocationGranularityMinimum, 0);
  VAL (hipMemHandleTypeNone, 0);
  VAL (hipDeviceAttributeVirtualMemoryManagementSupported, 89);
  printf ("%s\n", nfail == 0 ? "LAYOUT OK" : "LAYOUT WRONG");
  return nfail != 0;
}
