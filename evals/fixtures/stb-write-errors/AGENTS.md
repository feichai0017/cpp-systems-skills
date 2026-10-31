# Build and test

This repository is stb at commit 003501f, imported unchanged. Each library is a single
header that compiles as C and as C++. The image writer has a small test that writes
sample images into `tests/output/`:

```sh
cd tests
mkdir -p output
cc -I.. -DIWT_TEST image_write_test.c -lm -o image_write_test && ./image_write_test
```
