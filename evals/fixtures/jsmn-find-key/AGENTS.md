# Build and test

This repository is jsmn at commit 25647e6, imported unchanged: a single-header JSON
tokenizer in C89 that is also included from C++. `jsmn.h` declares its API with `JSMN_API`
and keeps the implementation under `#ifndef JSMN_HEADER`; `JSMN_STATIC`, `JSMN_STRICT`
and `JSMN_PARENT_LINKS` change how it is built. The tests run in all four combinations
of the last two:

```sh
make test
```
