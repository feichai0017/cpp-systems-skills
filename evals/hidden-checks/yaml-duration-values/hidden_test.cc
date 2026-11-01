// Reviewer-only behavior probe for yaml-duration-values. Build one family per translation
// unit with -DFAMILY_<name> and link the workspace's yaml-cpp, so that a family that does
// not compile cannot hide the others. Prints PASS/FAIL (HIT/MISS for soft families), exits 0.
#include <yaml-cpp/yaml.h>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <map>
#include <string>
#include <vector>

namespace {

using std::chrono::duration;
using frames = duration<long long, std::ratio<1, 30>>;

int failures = 0;
std::string first_failure;

void note(bool ok, const std::string& what) {
  if (!ok && failures++ == 0) first_failure = what;
}

void report(const char* family, bool soft = false) {
  if (failures == 0) std::printf("%s duration %s\n", soft ? "HIT" : "PASS", family);
  else std::printf("%s duration %s: %d case(s), first: %s\n", soft ? "MISS" : "FAIL", family, failures, first_failure.c_str());
}

template <typename T>
T parse(const std::string& text) {
  return YAML::Node(text).as<T>();
}

template <typename T>
void accepts(const std::string& text, typename T::rep expected) {
  try {
    T got = parse<T>(text);
    note(got.count() == expected, "\"" + text + "\" gives " + std::to_string(got.count())
         + ", expected " + std::to_string(expected));
  } catch (const std::exception& e) {
    note(false, "\"" + text + "\" throws " + e.what());
  }
}

// Rejections behave like any other failed conversion: as<T>() throws BadConversion.
template <typename T>
void rejects(const std::string& text) {
  try {
    T got = parse<T>(text);
    note(false, "\"" + text + "\" accepted as " + std::to_string(got.count()));
  } catch (const YAML::BadConversion&) {
  } catch (const std::exception& e) {
    note(false, "\"" + text + "\" throws a different exception: " + e.what());
  }
}

}  // namespace

int main() {
  using namespace std::chrono;
#if defined(FAMILY_units)
  accepts<milliseconds>("2s", 2000);
  accepts<seconds>("5min", 300);
  accepts<minutes>("1h", 60);
  accepts<nanoseconds>("250us", 250000);
  accepts<nanoseconds>("3ns", 3);
  accepts<microseconds>("7ms", 7000);
  accepts<hours>("2h", 2);
  accepts<seconds>("0s", 0);
  accepts<milliseconds>("1500ms", 1500);
  report("units");
#elif defined(FAMILY_exact)
  rejects<seconds>("1500ms");
  rejects<minutes>("90s");
  rejects<hours>("30min");
  accepts<seconds>("2000ms", 2);
  accepts<minutes>("120s", 2);
  accepts<frames>("2s", 60);
  accepts<frames>("100ms", 3);
  rejects<frames>("50ms");
  report("exact");
#elif defined(FAMILY_range)
  accepts<milliseconds>("-2s", -2000);
  rejects<duration<std::int32_t, std::nano>>("3s");
  rejects<duration<std::int32_t, std::nano>>("-3s");
  accepts<duration<std::int32_t, std::nano>>("2s", 2000000000);
  rejects<duration<short, std::milli>>("33s");
  accepts<duration<short, std::milli>>("32s", 32000);
  rejects<duration<unsigned, std::milli>>("-1s");
  accepts<duration<unsigned, std::milli>>("4s", 4000);
  rejects<nanoseconds>("9223372036854775807h");
  rejects<duration<std::int32_t>>("99999999999s");
  // Counts above 2^53 must stay exact: converting through double or long double (64 bits on
  // some targets) loses the low bits.
  accepts<nanoseconds>("9007199254740993ns", 9007199254740993LL);
  accepts<nanoseconds>("9007199254740993us", 9007199254740993000LL);
  report("range");
#elif defined(FAMILY_floating)
  {
    auto check = [](const std::string& text, double got, double expected) {
      note(got == expected, "\"" + text + "\" gives " + std::to_string(got));
    };
    try {
      check("1.5s", parse<duration<double>>("1.5s").count(), 1.5);
      check("250ms", parse<duration<double>>("250ms").count(), 0.25);
      check("1.5s as ms", parse<duration<double, std::milli>>("1.5s").count(), 1500.0);
      check("0.25min as float s", parse<duration<float>>("0.25min").count(), 15.0);
    } catch (const std::exception& e) {
      note(false, std::string("floating count throws ") + e.what());
    }
    rejects<seconds>("1.5s");
  }
  report("floating");
#elif defined(FAMILY_syntax)
  rejects<seconds>("5");
  rejects<seconds>("5sec");
  rejects<seconds>("");
  rejects<seconds>("s");
  rejects<seconds>("1h30m");
  rejects<seconds>("abc");
  rejects<seconds>("5x");
  report("syntax");
#elif defined(FAMILY_count_syntax)
  // The count is read as Rep is: yaml-cpp's stream conversion detects the base (hex, octal),
  // accepts a leading '+', and rejects '-' for unsigned counts.
  accepts<seconds>("+5s", 5);
  accepts<seconds>("0x10s", 16);
  accepts<seconds>("010s", 8);
  rejects<duration<unsigned long long>>("-0s");
  report("count syntax", true);
#elif defined(FAMILY_usage)
  try {
    YAML::Node doc = YAML::Load(
        "timeout: 1500ms\n"
        "retries: [1s, 2min, 3s]\n"
        "limits: {read: 250ms, write: 2s}\n"
        "bad: 1500ms\n"
        "nested: {a: 1}\n");
    note(doc["timeout"].as<milliseconds>().count() == 1500, "as<milliseconds>() after Load");
    auto retries = doc["retries"].as<std::vector<seconds>>();
    note(retries.size() == 3 && retries[1].count() == 120, "std::vector<seconds>");
    auto limits = doc["limits"].as<std::map<std::string, milliseconds>>();
    note(limits.size() == 2 && limits["write"].count() == 2000, "std::map<std::string, milliseconds>");
    note(doc["bad"].as<seconds>(seconds(7)).count() == 7, "as<seconds>(fallback) on an inexact value");
    note(doc["missing"].as<seconds>(seconds(9)).count() == 9, "as<seconds>(fallback) on a missing key");
    seconds direct;
    note(!YAML::convert<seconds>::decode(doc["nested"], direct), "convert<seconds>::decode on a map");
    bool threw = false;
    try { doc["nested"].as<seconds>(); } catch (const YAML::BadConversion&) { threw = true; }
    note(threw, "as<seconds>() on a map throws BadConversion");
  } catch (const std::exception& e) {
    note(false, std::string("usage throws ") + e.what());
  }
  report("usage");
#else
#error "define FAMILY_<name>"
#endif
  return 0;
}
