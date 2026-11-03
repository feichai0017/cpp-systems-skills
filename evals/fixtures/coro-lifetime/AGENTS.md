# Project conventions

C++20 without exceptions. Asynchronous code uses the project's `Task<T>` and `ManualExecutor` from `async.hpp`; tasks are lazy and start when awaited. Failures are reported as `std::error_code`. `store.hpp`, `service.hpp` and `check.cc` are the complete set of callers; `async.hpp` is shared infrastructure and should not change.

Build and check from this directory with the compiler in `$CXX` (defaults to `c++`); the check runs under AddressSanitizer:

```sh
${CXX:-c++} -std=c++20 -Wall -Wextra -pedantic -Werror -g -fsanitize=address check.cc -o check
./check
```
