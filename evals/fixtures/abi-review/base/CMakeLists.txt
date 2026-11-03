cmake_minimum_required(VERSION 3.20)
project(kvclient VERSION 1.2.0 LANGUAGES CXX)

add_library(kvclient SHARED src/client.cc)
target_include_directories(kvclient PUBLIC "${PROJECT_SOURCE_DIR}/include")
target_compile_features(kvclient PUBLIC cxx_std_20)
set_target_properties(kvclient PROPERTIES VERSION ${PROJECT_VERSION} SOVERSION 1)
