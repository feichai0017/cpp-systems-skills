// Reviewer-only behavior probe for cxxopts-duration-values. Build one family per
// translation unit with -DFAMILY_<name>, so that a family that does not compile
// cannot hide the others. Prints PASS/FAIL lines and exits 0.
#include <cxxopts.hpp>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace {

using std::chrono::duration;
using frames = duration<long long, std::ratio<1, 30>>;

int failures = 0;
std::string first_failure;

void note(bool ok, const std::string& what)
{
  if (!ok && failures++ == 0) first_failure = what;
}

// Parses "--dur=<text>" into an option of type T.
template <typename T>
T parse(const std::string& text)
{
  cxxopts::Options options("probe");
  options.add_options()("dur", "duration", cxxopts::value<T>());
  std::string arg = "--dur=" + text;
  const char* argv[] = {"probe", arg.c_str(), nullptr};
  auto result = options.parse(2, argv);
  return result["dur"].as<T>();
}

template <typename T>
void accepts(const std::string& text, typename T::rep expected)
{
  try {
    T got = parse<T>(text);
    note(got.count() == expected, "\"" + text + "\" gives " + std::to_string(got.count())
         + ", expected " + std::to_string(expected));
  } catch (const std::exception& e) {
    note(false, "\"" + text + "\" throws " + e.what());
  }
}

// Rejections must be the exception every other unparsable value raises.
template <typename T>
void rejects(const std::string& text)
{
  try {
    T got = parse<T>(text);
    note(false, "\"" + text + "\" accepted as " + std::to_string(got.count()));
  } catch (const cxxopts::exceptions::incorrect_argument_type&) {
  } catch (const std::exception& e) {
    note(false, "\"" + text + "\" throws a different exception: " + e.what());
  }
}

void report(const char* family)
{
  if (failures == 0) std::printf("PASS duration %s\n", family);
  else std::printf("FAIL duration %s: %d case(s), first: %s\n", family, failures, first_failure.c_str());
}

}  // namespace

int main()
{
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
  // cxxopts' integer_parser takes std::abs of the minimum for every negative count, which is
  // undefined for 64-bit counts; negative cases use 32-bit counts so the sanitizer sees only new code.
  accepts<duration<int, std::milli>>("-2s", -2000);
  rejects<duration<std::int32_t, std::nano>>("3s");
  rejects<duration<std::int32_t, std::nano>>("-3s");
  accepts<duration<std::int32_t, std::nano>>("2s", 2000000000);
  rejects<duration<short, std::milli>>("33s");
  accepts<duration<short, std::milli>>("32s", 32000);
  rejects<duration<unsigned, std::milli>>("-1s");
  accepts<duration<unsigned, std::milli>>("4s", 4000);
  rejects<nanoseconds>("9223372036854775807h");
  rejects<duration<std::int32_t>>("99999999999s");
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
#elif defined(FAMILY_usage)
  {
    cxxopts::Options options("probe");
    options.add_options()
      ("t,timeout", "", cxxopts::value<milliseconds>()->default_value("5s"))
      ("i,interval", "", cxxopts::value<seconds>()->implicit_value("1min"))
      ("l,list", "", cxxopts::value<std::vector<seconds>>())
      ("rest", "", cxxopts::value<std::vector<minutes>>());
    options.parse_positional("rest");
    const char* argv[] = {"probe", "--interval", "--list=1s,2min", "--list", "3s", "1h", "2h", nullptr};
    try {
      auto r = options.parse(7, argv);
      note(r["timeout"].as<milliseconds>().count() == 5000, "default_value(\"5s\")");
      note(r["interval"].as<seconds>().count() == 60, "implicit_value(\"1min\")");
      auto list = r["list"].as<std::vector<seconds>>();
      note(list.size() == 3 && list[0].count() == 1 && list[1].count() == 120 && list[2].count() == 3,
           "std::vector<seconds> from \"1s,2min\" and \"3s\"");
      auto rest = r["rest"].as<std::vector<minutes>>();
      note(rest.size() == 2 && rest[0].count() == 60 && rest[1].count() == 120, "positional std::vector<minutes>");
      bool found = false;
      for (const auto& kv : r.arguments())
        if (kv.key() == "list" && kv.value() == "3s") found = kv.as<seconds>().count() == 3;
      note(found, "KeyValue::as<seconds>()");
    } catch (const std::exception& e) {
      note(false, std::string("parse throws ") + e.what());
    }
  }
  report("usage");
#elif defined(FAMILY_optional)
  {
    cxxopts::Options options("probe");
    options.add_options()
      ("o", "", cxxopts::value<std::optional<seconds>>())
      ("p", "", cxxopts::value<seconds>());
    const char* argv[] = {"probe", "-o", "2min", "-p", "3s", nullptr};
    try {
      auto r = options.parse(5, argv);
      auto o = r["o"].as<std::optional<seconds>>();
      note(o && o->count() == 120, "std::optional<seconds>");
      auto p = r.as_optional<seconds>("p");
      note(p && p->count() == 3, "as_optional<seconds>");
    } catch (const std::exception& e) {
      note(false, std::string("parse throws ") + e.what());
    }
  }
  report("optional");
#else
#error "define FAMILY_<name>"
#endif
  return 0;
}
