# Project conventions

Use C++20 without exceptions. Fallible operations return the project's `Result<T>` from `result.hpp`; do not introduce another error type. `checksum.hpp`, `config.hpp` and `check.cc` are the complete set of callers. Checksum values must not change.

Build and check from this directory:

```sh
g++ -std=c++20 -Wall -Wextra -pedantic -Werror check.cc -o check
./check
```
