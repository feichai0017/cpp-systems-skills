// Existing ways to construct INIReader from a file name must keep reading the file.
// TEST_INI is the path of examples/test.ini as a string literal.
#include <cstdio>
#include <string>

#include "INIReader.h"

namespace {

int g_failures = 0;

void Expect(INIReader& reader, const char* form) {
  bool ok = reader.ParseError() == 0 && reader.Get("user", "name", "?") == "Bob Smith" &&
            reader.GetInteger("protocol", "version", -1) == 6;
  std::printf("%s INIReader(%s) still parses the named file\n", ok ? "PASS" : "FAIL", form);
  if (!ok) ++g_failures;
}

}  // namespace

int main() {
  {
    INIReader reader(TEST_INI);
    Expect(reader, "string literal");
  }
  {
    const char* path = TEST_INI;
    INIReader reader(path);
    Expect(reader, "const char* variable");
  }
  {
    std::string path = TEST_INI;
    INIReader reader(path);
    Expect(reader, "std::string");
  }
  return g_failures;
}
