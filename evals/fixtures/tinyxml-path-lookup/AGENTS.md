# Build and test

This repository is TinyXML 2.6.2, imported unchanged.

```sh
make clean && make && ./xmltest                       # build without STL support
make clean && make TINYXML_USE_STL=YES && ./xmltest   # build with STL support
```
