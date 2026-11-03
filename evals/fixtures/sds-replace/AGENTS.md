# Build and test

This repository is sds (Simple Dynamic Strings, the string library of Redis) at commit
5347739, imported unchanged. It is C99. Functions are declared in `sds.h`, implemented
and unit-tested in `sds.c` (the tests run under `SDS_TEST_MAIN`), and documented in
`README.md`:

```sh
make && ./sds-test
```
