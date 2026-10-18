# Project conventions

Use C++17 and preserve the current public API. This component runs synchronously on one thread.

Build and check from this directory:

```sh
g++ -std=c++17 -Wall -Wextra -pedantic check.cc -o check
./check
```
