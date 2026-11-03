# Build and test

This repository is TinyXML-2 2.2.0, imported unchanged. The bundled Makefile passes
the header to the compiler, which current Clang rejects; build the test directly:

```sh
c++ -o xmltest xmltest.cpp tinyxml2.cpp && ./xmltest
```
