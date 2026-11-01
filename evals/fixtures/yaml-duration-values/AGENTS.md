# Build and test

This repository is yaml-cpp 0.9.0, imported unchanged. The library targets C++11 and is
built by CI with GCC, Clang and MSVC (see `.github/workflows/build.yml`). Conversions
between nodes and C++ types are the `YAML::convert<T>` specializations in
`include/yaml-cpp/node/convert.h`; node tests are in `test/node/node_test.cpp`:

```sh
cmake -S . -B build -DYAML_CPP_BUILD_TESTS=ON
cmake --build build -j8 && ./build/test/yaml-cpp-tests
```
