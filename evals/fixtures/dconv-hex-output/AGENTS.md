# Build and test

This repository is double-conversion 3.4.0, imported unchanged. The library is plain
C++98 (it builds without warnings under `-std=c++98 -pedantic` with GCC and Clang) and
uses `DOUBLE_CONVERSION_ASSERT` for internal preconditions. Each public method is
documented in its header. The conversion tests are in `test/cctest/test-conversions.cc`:

```sh
cmake -S . -B cmake-build -DBUILD_TESTING=ON
cmake --build cmake-build -j8 && ctest --test-dir cmake-build --output-on-failure
```
