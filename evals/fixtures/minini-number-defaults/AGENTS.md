# Build and test

This repository is minIni at commit 1bb6557, imported unchanged. The tests read and
rewrite `dev/test.ini` and `dev/testplain.ini`, and leave them as they were:

```sh
cd dev
cc -o test test.c minIni.c && ./test
cc -c minIni.c -o minIni.o && c++ -o test2 test2.cc minIni.o && ./test2
```
