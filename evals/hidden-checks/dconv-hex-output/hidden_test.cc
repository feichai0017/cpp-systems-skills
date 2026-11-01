// Reviewer-only behavior probe for dconv-hex-output. Normal numbers are compared with the C
// library's "%a" (which agrees on normals); denormals, zeros and special values with
// expectations built here. Prints PASS/FAIL lines and exits 0.
#include <double-conversion/double-to-string.h>
#include <double-conversion/ieee.h>

#include <cstdio>
#include <cstring>
#include <stdint.h>
#include <string>

using double_conversion::Double;
using double_conversion::DoubleToStringConverter;
using double_conversion::StringBuilder;

namespace {

int failures = 0;
std::string first_failure;

void note(bool ok, const std::string& what) {
  if (!ok && failures++ == 0) first_failure = what;
}

std::string hex(const DoubleToStringConverter& dc, double value, bool* ok) {
  char buffer[64];
  StringBuilder builder(buffer, sizeof buffer);
  *ok = dc.ToHexadecimal(value, &builder);
  return builder.Finalize();
}

void expect(const DoubleToStringConverter& dc, double value, const char* expected, const char* label) {
  bool ok = false;
  const std::string got = hex(dc, value, &ok);
  note(ok && got == expected, std::string(label) + " gives \"" + got + "\"" + (ok ? "" : " and false") +
       ", expected \"" + expected + "\"");
}

double bits(uint64_t value) { return Double(value).value(); }

void report(const char* family) {
  if (failures == 0) std::printf("PASS hex %s\n", family);
  else std::printf("FAIL hex %s: %d case(s), first: %s\n", family, failures, first_failure.c_str());
  failures = 0;
  first_failure.clear();
}

}  // namespace

int main() {
  const DoubleToStringConverter dc(DoubleToStringConverter::NO_FLAGS, "Infinity", "NaN", 'e', -6, 21, 0, 0);

  expect(dc, 1.0, "0x1p+0", "1.0");
  expect(dc, 3.0, "0x1.8p+1", "3.0");
  expect(dc, 0.1, "0x1.999999999999ap-4", "0.1");
  expect(dc, 0.5, "0x1p-1", "0.5");
  expect(dc, 1024.0, "0x1p+10", "1024");
  expect(dc, -2.5, "-0x1.4p+1", "-2.5");
  expect(dc, bits(0x3FF0000000000001ULL), "0x1.0000000000001p+0", "1 + 2^-52");
  expect(dc, bits(0x7FEFFFFFFFFFFFFFULL), "0x1.fffffffffffffp+1023", "DBL_MAX");
  expect(dc, bits(0xFFEFFFFFFFFFFFFFULL), "-0x1.fffffffffffffp+1023", "-DBL_MAX");
  expect(dc, bits(0x0010000000000000ULL), "0x1p-1022", "DBL_MIN");
  expect(dc, bits(0x0018000000000000ULL), "0x1.8p-1022", "1.5 * DBL_MIN");
  // Every normal double the C library prints the same way.
  uint64_t state = 0x9E3779B97F4A7C15ULL;
  for (int i = 0; i < 20000; i++) {
    state = state * 6364136223846793005ULL + 1442695040888963407ULL;
    const uint64_t raw = state ^ (state >> 29);
    const uint64_t exponent = (raw >> 52) & 0x7FF;
    if (exponent == 0 || exponent == 0x7FF) continue;
    const double value = bits(raw);
    char expected[64];
    std::snprintf(expected, sizeof expected, "%a", value);
    expect(dc, value, expected, "random normal");
  }
  report("normal");

  expect(dc, bits(1), "0x0.0000000000001p-1022", "smallest denormal");
  expect(dc, bits(0x000FFFFFFFFFFFFFULL), "0x0.fffffffffffffp-1022", "largest denormal");
  expect(dc, bits(0x0008000000000000ULL), "0x0.8p-1022", "2^-1023");
  expect(dc, bits(0x8000000000000010ULL), "-0x0.000000000001p-1022", "negative denormal");
  for (uint64_t fraction = 1; fraction < (1ULL << 52); fraction = fraction * 3 + 7) {
    std::string digits;
    for (int shift = 48; shift >= 0; shift -= 4) digits += "0123456789abcdef"[(fraction >> shift) & 0xF];
    digits.erase(digits.find_last_not_of('0') + 1);
    expect(dc, bits(fraction), ("0x0." + digits + "p-1022").c_str(), "denormal");
  }
  report("denormal");

  expect(dc, 0.0, "0x0p+0", "0.0");
  expect(dc, -0.0, "-0x0p+0", "-0.0");
  const DoubleToStringConverter unique(DoubleToStringConverter::UNIQUE_ZERO, "Infinity", "NaN", 'e', -6, 21, 0, 0);
  expect(unique, -0.0, "0x0p+0", "-0.0 with UNIQUE_ZERO");
  expect(unique, -1.0, "-0x1p+0", "-1.0 with UNIQUE_ZERO");
  report("zero");

  expect(dc, Double::Infinity(), "Infinity", "infinity");
  expect(dc, -Double::Infinity(), "-Infinity", "-infinity");
  expect(dc, Double::NaN(), "NaN", "NaN");
  const DoubleToStringConverter none(DoubleToStringConverter::NO_FLAGS, NULL, NULL, 'e', -6, 21, 0, 0);
  bool ok = true;
  std::string got = hex(none, Double::Infinity(), &ok);
  note(!ok && got.empty(), "infinity without a symbol gives \"" + got + "\"" + (ok ? " and true" : ""));
  got = hex(none, Double::NaN(), &ok);
  note(!ok && got.empty(), "NaN without a symbol gives \"" + got + "\"" + (ok ? " and true" : ""));
  report("special");

  // The flags and exponent character of the decimal conversions do not change "%a" output.
  const DoubleToStringConverter other(DoubleToStringConverter::EMIT_POSITIVE_EXPONENT_SIGN |
                                      DoubleToStringConverter::EMIT_TRAILING_DECIMAL_POINT |
                                      DoubleToStringConverter::EMIT_TRAILING_ZERO_AFTER_POINT,
                                      "Infinity", "NaN", 'E', -6, 21, 0, 0);
  expect(other, 1.0, "0x1p+0", "1.0 with trailing-point flags and 'E'");
  expect(other, 0.25, "0x1p-2", "0.25 with trailing-point flags and 'E'");
  report("flags");
  return 0;
}
