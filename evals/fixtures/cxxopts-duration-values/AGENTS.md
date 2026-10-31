# Build and test

This repository is cxxopts 3.3.1, imported unchanged. The library is header-only
(`include/cxxopts.hpp`) and supports C++11 and later. The tests use the bundled Catch
and build with the project's warnings as errors; `std::optional` tests need C++17:

```sh
cmake -S . -B build -DCXXOPTS_BUILD_TESTS=ON
cmake --build build --target options_test -j8 && ./build/test/options_test
cmake -S . -B build17 -DCXXOPTS_BUILD_TESTS=ON -DCXXOPTS_CXX_STANDARD=17
cmake --build build17 --target options_test -j8 && ./build17/test/options_test
```
