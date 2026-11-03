// Reviewer-only probe: the C++ minIni class follows the same DefValue contract,
// including int range for geti. Usage: hidden_wrapper <dir>
#include <climits>
#include <cstdio>
#include <string>
#include "minIni.h"

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  std::string path = std::string(argv[1]) + "/wrapper.ini";
  std::FILE* f = std::fopen(path.c_str(), "w");
  if (!f) return 2;
  std::fprintf(f, "[g]\nbig=3000000000\nnbig=-3000000000\nmax=2147483647\nmin=-2147483648\n"
                  "bad=12abc\nok=12\nreal=abc\n");
  std::fclose(f);
  minIni ini(path);
  struct { const char* key; int expected; } geti[] = {
    {"big", 77}, {"nbig", 77}, {"max", INT_MAX}, {"min", INT_MIN}, {"bad", 77}, {"ok", 12}, {"absent", 77}};
  std::string failures;
  for (unsigned i = 0; i < sizeof geti / sizeof geti[0]; ++i) {
    int got = ini.geti("g", geti[i].key, 77);
    if (got != geti[i].expected) {
      char item[96];
      std::sprintf(item, ", %s -> %d (want %d)", geti[i].key, got, geti[i].expected);
      failures += item;
    }
  }
  if (failures.empty()) std::printf("PASS minIni::geti returns DefValue outside int range and on bad input\n");
  else std::printf("FAIL minIni::geti: %s\n", failures.c_str() + 2);
  bool wrappers = ini.getl("g", "bad", 5) == 5 && ini.getl("g", "big", 5) == 3000000000L;
#if defined INI_REAL
  wrappers = wrappers && ini.getf("g", "real", 2.5f) == 2.5f;
#endif
  std::printf(wrappers ? "PASS minIni::getl and getf follow ini_getl and ini_getf\n"
                       : "FAIL minIni::getl or getf disagree with the C functions\n");
  return failures.empty() && wrappers ? 0 : 1;
}
