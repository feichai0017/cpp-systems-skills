cmake_minimum_required(VERSION 3.20)
project(kvstore LANGUAGES CXX)

set(CMAKE_CXX_EXTENSIONS OFF)

add_library(kvstore_base INTERFACE)
target_include_directories(kvstore_base INTERFACE "${PROJECT_SOURCE_DIR}/include")
target_compile_features(kvstore_base INTERFACE cxx_std_20)

add_library(kvstore_checksum STATIC src/checksum/crc32.cc)
target_include_directories(kvstore_checksum PUBLIC "${PROJECT_SOURCE_DIR}/src")
target_compile_features(kvstore_checksum PUBLIC cxx_std_20)

add_library(kvstore_storage STATIC src/storage/segment.cc)
target_include_directories(kvstore_storage PUBLIC "${PROJECT_SOURCE_DIR}/include")
target_link_libraries(kvstore_storage PUBLIC kvstore_base)

enable_testing()
add_executable(segment_test tests/storage/segment_test.cc)
target_link_libraries(segment_test PRIVATE kvstore_storage)
add_test(NAME segment_test COMMAND segment_test)
