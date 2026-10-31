# Project conventions

Use C++20 without exceptions. System-level failures are reported as `std::error_code`; an empty `std::error_code` means success. The write function is injected so tests can simulate the OS: it returns the number of bytes written, or `-1` with `errno` set. `io.hpp` and `check.cc` are the complete set of callers.

Build and check from this directory:

```sh
g++ -std=c++20 -Wall -Wextra -pedantic -Werror check.cc -o check
./check
```
