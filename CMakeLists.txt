cmake_minimum_required (VERSION 3.18)
project (fiatallocators LANGUAGES Fortran)

# Compilers: nvfortran (NVIDIA: OpenACC, CUDA) or amdflang (AMD: OpenMP offload, HIP)
if (CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
  set (FA_COMPILER_VENDOR "nvidia")
elseif (CMAKE_Fortran_COMPILER_ID STREQUAL "LLVMFlang")
  set (FA_COMPILER_VENDOR "amd")
else ()
  message (FATAL_ERROR "fiatallocators is built with nvfortran or amdflang only")
endif ()

# Options
option (ENABLE_GPU "Build the GPU allocators" OFF)
option (ENABLE_MPI "Build the MPI tests" OFF)
set (GPU_VENDOR "${FA_COMPILER_VENDOR}" CACHE STRING
     "GPU helper set (src/gpu_helpers_<vendor>.F90): nvidia (OpenACC, CUDA) or amd (OpenMP, HIP)")
set (GPU_CC "cc90" CACHE STRING "NVIDIA: -gpu= target (cc80: A100, cc90: GH200)")
set (GPU_ARCH "gfx90a" CACHE STRING "AMD: --offload-arch= target (gfx90a: MI210, MI250; gfx942: MI300A, MI300X)")

# fypp generates the type/kind/rank variants
find_program (FYPP fypp HINTS $ENV{FYPP_DIR} $ENV{PERM}/venv-fypp-aarch64/bin REQUIRED)

set (CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules)
if (FA_COMPILER_VENDOR STREQUAL "nvidia")
  set (CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Mpreprocess")
else ()
  set (CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -cpp")
endif ()

if (ENABLE_GPU)
  if (NOT GPU_VENDOR STREQUAL FA_COMPILER_VENDOR)
    message (FATAL_ERROR "GPU_VENDOR=${GPU_VENDOR} needs the ${GPU_VENDOR} compiler")
  endif ()
  if (GPU_VENDOR STREQUAL "nvidia")
    set (OFFLOAD_FLAGS -acc=gpu -gpu=${GPU_CC})
    # libcuda: the driver API (VMM); the stub library is enough at link time
    find_library (CUDA_DRIVER_LIBRARY cuda
      HINTS $ENV{NVHPC_CUDA_HOME}/lib64/stubs $ENV{CUDA_HOME}/lib64/stubs REQUIRED)
    find_library (CUDA_RUNTIME_LIBRARY cudart
      HINTS $ENV{NVHPC_CUDA_HOME}/lib64 $ENV{CUDA_HOME}/lib64 REQUIRED)
    set (GPU_LIBRARIES ${CUDA_DRIVER_LIBRARY} ${CUDA_RUNTIME_LIBRARY})
  elseif (GPU_VENDOR STREQUAL "amd")
    set (OFFLOAD_FLAGS -fopenmp --offload-arch=${GPU_ARCH})
    # libamdhip64: HIP (VMM API, graphs in the tests)
    find_library (HIP_LIBRARY amdhip64 HINTS $ENV{ROCM_PATH}/lib /opt/rocm/lib REQUIRED)
    set (GPU_LIBRARIES ${HIP_LIBRARY})
  else ()
    message (FATAL_ERROR "GPU_VENDOR must be nvidia or amd")
  endif ()
endif ()

# fypp_generate (<output.F90> <input.fypp>)
function (fypp_generate OUT IN)
  add_custom_command (OUTPUT ${OUT}
    COMMAND ${FYPP} -n ${IN} ${OUT}
    DEPENDS ${IN}
    COMMENT "fypp ${IN}")
endfunction ()

add_subdirectory (src)

enable_testing ()
add_subdirectory (tests)
