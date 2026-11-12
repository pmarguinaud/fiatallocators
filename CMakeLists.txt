cmake_minimum_required (VERSION 3.18)
project (fiatallocators LANGUAGES Fortran)

# Options
option (ENABLE_GPU "Build the GPU allocators (OpenACC, CUDA driver VMM API)" OFF)
option (ENABLE_MPI "Build the MPI tests" OFF)
set (GPU_CC "cc90" CACHE STRING "GPU compute capability for nvfortran -gpu= (cc80: A100, cc90: GH200)")
set (GPU_VENDOR "nvidia" CACHE STRING "GPU helper set: nvidia (amd later)")

if (NOT CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
  message (FATAL_ERROR "fiatallocators is built with nvfortran only")
endif ()

# fypp generates the type/kind/rank variants
find_program (FYPP fypp HINTS $ENV{FYPP_DIR} $ENV{PERM}/venv-fypp-aarch64/bin REQUIRED)

set (CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules)
set (CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Mpreprocess")
if (ENABLE_GPU)
  set (ACC_FLAGS -acc=gpu -gpu=${GPU_CC})
  # libcuda: the driver API (VMM); the stub library is enough at link time
  find_library (CUDA_DRIVER_LIBRARY cuda
    HINTS $ENV{NVHPC_CUDA_HOME}/lib64/stubs $ENV{CUDA_HOME}/lib64/stubs REQUIRED)
  find_library (CUDA_RUNTIME_LIBRARY cudart
    HINTS $ENV{NVHPC_CUDA_HOME}/lib64 $ENV{CUDA_HOME}/lib64 REQUIRED)
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
