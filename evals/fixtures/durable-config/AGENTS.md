# Project conventions

C++20 without exceptions. Failures are reported as `std::error_code`; an empty value means success. All file access goes through `project::fs::FileSystem` (`fs.hpp`); `posix_fs.hpp` is the production implementation and tests may substitute fakes. The `FileSystem` interface is shared with other components and must not change. `config_store.hpp` and `check.cc` are the complete set of callers.

Build and check from this directory:

```sh
g++ -std=c++20 -Wall -Wextra -pedantic -Werror check.cc -o check
./check
```
