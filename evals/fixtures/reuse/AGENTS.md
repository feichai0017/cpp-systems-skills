# Project conventions

Use C++17, PascalCase functions and the existing error behavior. Keep changes local to the requested behavior.

Build and check from this directory:

```sh
g++ -std=c++17 -Wall -Wextra -pedantic -I. operation.cc check.cc -o check
./check
```
