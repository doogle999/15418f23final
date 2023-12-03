cmake_minimum_required(VERSION 3.27)
project(fuzzer LANGUAGES CXX CUDA)

set(CMAKE_CUDA_STANDARD 23)

message(STATUS "C++ compiler ID: ${CMAKE_CXX_COMPILER_ID}")
message(STATUS "C++ compiler version: ${CMAKE_CXX_COMPILER_VERSION}")

add_executable(fuzzer src/main.cu)

# Add packages. For now, most of these aren't necessary.

#find_package(fmt CONFIG REQUIRED)
#target_link_libraries(fuzzer PRIVATE fmt::fmt)
#
#find_package(asmjit CONFIG REQUIRED)
#target_link_libraries(fuzzer PRIVATE asmjit::asmjit)
#
#find_package(doctest CONFIG REQUIRED)
#target_link_libraries(fuzzer PRIVATE doctest::doctest)

#find_package(MPI)
#add_definitions(-DOMPI_SKIP_MPICXX)

include_directories(SYSTEM ${MPI_INCLUDE_PATH})
target_link_libraries(fuzzer PRIVATE ${MPI_C_LIBRARIES})

find_package(Boost REQUIRED COMPONENTS mpi serialization)
target_link_libraries(fuzzer ${Boost_LIBRARIES})

set_target_properties(fuzzer PROPERTIES
        CUDA_SEPARABLE_COMPILATION ON)
