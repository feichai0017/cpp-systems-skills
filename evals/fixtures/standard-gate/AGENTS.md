# Project conventions

The production toolchain is fixed at C++14 and cannot be upgraded. Lookups that may find nothing return a `const T*` that is `nullptr` when missing, as `FindConfig` in `config_store.hpp` does. Use PascalCase functions and a trailing underscore for private members. `registry.hpp`, `config_store.hpp` and `check.cc` are the complete set of callers.

Build and check from this directory:

```sh
g++ -std=c++14 -Wall -Wextra -pedantic -Werror check.cc -o check
./check
```
