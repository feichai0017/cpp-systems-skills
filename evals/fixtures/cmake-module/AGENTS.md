# Project conventions

C++20 without exceptions. Fallible operations return `kvstore::Result<T>` from `include/kvstore/base/result.h`. Public headers live under `include/kvstore/`; implementation files and internal headers live under `src/`. Types and functions use PascalCase; private members use a trailing underscore.

Build and test from this directory:

```sh
cmake -S . -B build -G Ninja
cmake --build build
ctest --test-dir build --output-on-failure
```
