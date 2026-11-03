# Project conventions

C++20 without exceptions. Fallible operations return `project::Result<T>` from `result.hpp`. The wire protocol is defined in `protocol.hpp` and is little-endian on the wire; payloads larger than `kMaxPayloadBytes` are rejected with `DecodeError::kTooLarge`. `decoder.hpp` and `check.cc` are the complete set of callers.

Build and check from this directory with the compiler in `$CXX` (defaults to `c++`):

```sh
${CXX:-c++} -std=c++20 -Wall -Wextra -pedantic -Werror -g -fsanitize=address,undefined check.cc -o check
./check
```
