# Project conventions

`libkvclient` is a C++20 shared library. Releases are tagged; `libkvclient.so.1` (CMake `SOVERSION 1`) is shipped as a binary to other teams, who link against it without recompiling when we release a new minor version. Public headers live in `include/kvclient/`.

Build from this directory:

```sh
cmake -S . -B build -G Ninja
cmake --build build
```
