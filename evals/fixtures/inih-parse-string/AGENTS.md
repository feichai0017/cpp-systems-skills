# Build and test

This repository is inih r30, imported unchanged. The C tests print their results and
compare them with the checked-in baselines:

```sh
cd tests
cc -I.. ../ini.c unittest.c -o unittest && ./unittest | diff --strip-trailing-cr - baseline_multi.txt
cc -I.. -DINI_ALLOW_MULTILINE=0 ../ini.c unittest.c -o unittest && ./unittest | diff --strip-trailing-cr - baseline_single.txt
cc -I.. -DINI_STOP_ON_FIRST_ERROR=1 ../ini.c unittest.c -o unittest && ./unittest | diff --strip-trailing-cr - baseline_stop_on_first_error.txt
cd ../cpp
cc -I.. -c ../ini.c -o ini.o && c++ -I.. INIReader.cpp INIReaderTest.cpp ini.o -o INIReaderTest && ./INIReaderTest
```
