# Build and test

This repository is utf8proc 2.12.0, imported unchanged: a C99 library. Every public
function is declared and documented in `utf8proc.h` and implemented in `utf8proc.c`.
`make check` downloads Unicode data and needs network access; these tests run offline:

```sh
make test/charwidth test/misc test/valid test/iterate test/custom
test/charwidth && test/misc && test/valid && test/iterate && test/custom
```
