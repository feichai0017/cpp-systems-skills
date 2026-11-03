# Build and test

This repository is cpp-httplib 0.12.3, imported unchanged. `httplib.h` is a single
C++11 header. The tests use the bundled googletest. The `ServerTest` suite runs offline
against a local server; tests that reach external hosts fail without network access.

```sh
cd test
c++ -std=c++11 -I.. -I. test.cc include_httplib.cc gtest/gtest-all.cc gtest/gtest_main.cc -pthread -o test
./test --gtest_filter='ServerTest.*'
```
