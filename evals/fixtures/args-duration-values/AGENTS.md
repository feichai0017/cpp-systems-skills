# Build and test

This repository is args 6.6.1 (Taywee/args), imported unchanged. The library is the
single header `args.hxx` and supports C++11. Each `test/<name>.cxx` is its own test
executable, built with warnings as errors:

```sh
cmake -S . -B build && cmake --build build -j8 && ctest --test-dir build --output-on-failure
```
