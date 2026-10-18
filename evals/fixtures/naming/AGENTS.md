# Project conventions

Use C++17, PascalCase type/function names and a trailing underscore for private members. The header and check.cc are the complete set of callers. Keep runtime behavior unchanged.

Build and check from this directory:

```sh
g++ -std=c++17 -Wall -Wextra -pedantic check.cc -o check
./check
```
