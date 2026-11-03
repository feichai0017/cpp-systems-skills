# Build and test

This repository is {fmt} 9.1.0, imported unchanged. The library supports C++11 and
later. Tests use the bundled googletest; the formatters for standard library types are
tested in `test/std-test.cc`:

```sh
cmake -S . -B build -DFMT_TEST=ON -DCMAKE_CXX_STANDARD=17
cmake --build build --target std-test -j8 && ./build/bin/std-test
```
