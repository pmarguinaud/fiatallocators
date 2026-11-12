fypp_generate (${CMAKE_CURRENT_BINARY_DIR}/allocator_base_mod.F90 ${CMAKE_CURRENT_SOURCE_DIR}/allocator_base_mod.fypp)

set (SOURCES
  parkind1.F90
  abor1.F90
  allocator_params_mod.F90
  host_helpers_mod.F90
  ${CMAKE_CURRENT_BINARY_DIR}/allocator_base_mod.F90
  stack_core_mod.F90
  peak_core_mod.F90
  doublestack_cpu_mod.F90
  fixed_cpu_mod.F90
  peak_cpu_mod.F90
  new_allocator_mod.F90)

if (ENABLE_GPU)
  list (APPEND SOURCES
    gpu_helpers_${GPU_VENDOR}.F90
    doublestack_gpu_mod.F90
    fixed_gpu_mod.F90
    peak_gpu_mod.F90)
endif ()

add_library (fiatallocators STATIC ${SOURCES})
target_include_directories (fiatallocators PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_Fortran_MODULE_DIRECTORY})
if (ENABLE_GPU)
  target_compile_definitions (fiatallocators PUBLIC WITH_GPU)
  target_compile_options (fiatallocators PUBLIC ${ACC_FLAGS})
  target_link_options (fiatallocators PUBLIC ${ACC_FLAGS})
  target_link_libraries (fiatallocators PUBLIC ${CUDA_DRIVER_LIBRARY} ${CUDA_RUNTIME_LIBRARY})
endif ()
