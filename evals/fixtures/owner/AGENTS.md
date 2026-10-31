# Project conventions

Use C++17 without exceptions. Queries that may have no valid result return `std::optional`. `c_region.h` simulates an external C library and must not be modified; `loader.hpp` and `check.cc` are the complete set of callers.

Build and check from this directory:

```sh
g++ -std=c++17 -Wall -Wextra -pedantic -Werror check.cc -o check
./check
```
