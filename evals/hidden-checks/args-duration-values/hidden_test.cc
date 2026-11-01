// Reviewer-only behavior probe for args-duration-values. Build one family per
// translation unit with -DFAMILY_<name>, so that a family that does not compile
// cannot hide the others. Prints PASS/FAIL (or HIT/MISS for soft families) and exits 0.
#include <args.hxx>

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

void report(const char* family, bool soft = false)
{
  if (failures == 0) std::printf("%s duration %s\n", soft ? "HIT" : "PASS", family);
  else std::printf("%s duration %s: %d case(s), first: %s\n", soft ? "MISS" : "FAIL", family, failures, first_failure.c_str());
}

#ifndef ARGS_NOEXCEPT
// Parses "--dur=<text>" into a ValueFlag<T>.
template <typename T>
T parse(const std::string& text)
{
  args::ArgumentParser parser("probe");
  args::ValueFlag<T> flag(parser, "DUR", "duration", {"dur"});
  parser.ParseArgs(std::vector<std::string>{"--dur=" + text});
  return args::get(flag);
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
  } catch (const args::ParseError&) {
  } catch (const std::exception& e) {
    note(false, "\"" + text + "\" throws a different exception: " + e.what());
  }
}
#endif

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
  // The count is written as the Rep's own values are: args reads integers with strtoll/strtoull
  // in base 0 (hex, octal, leading '+', surrounding spaces) and floats with a classic-locale stream.
  accepts<seconds>(" 5s", 5);
  accepts<seconds>("+5s", 5);
  accepts<seconds>("0x10s", 16);
  accepts<seconds>("010s", 8);
  try {
    note(parse<duration<double>>(" 2.5s").count() == 2.5, "\" 2.5s\" as duration<double>");
  } catch (const std::exception& e) {
    note(false, std::string("\" 2.5s\" throws ") + e.what());
  }
  report("count syntax", true);
#elif defined(FAMILY_usage)
  {
    args::ArgumentParser parser("probe");
    args::ValueFlag<milliseconds> timeout(parser, "TIMEOUT", "", {"timeout"}, milliseconds(5000));
    args::ValueFlagList<seconds> list(parser, "LIST", "", {"list"});
    args::NargsValueFlag<milliseconds> pair(parser, "PAIR", "", {"pair"}, 2);
    args::Positional<minutes> first(parser, "FIRST", "");
    args::PositionalList<seconds> rest(parser, "REST", "");
    try {
      parser.ParseArgs(std::vector<std::string>{"--list=1s", "--list", "2min", "--pair", "1s", "250ms", "1h", "3s", "4s"});
      note(args::get(timeout).count() == 5000, "ValueFlag default value");
      auto l = args::get(list);
      note(l.size() == 2 && l[0].count() == 1 && l[1].count() == 120, "ValueFlagList<seconds>");
      auto p = args::get(pair);
      note(p.size() == 2 && p[0].count() == 1000 && p[1].count() == 250, "NargsValueFlag<milliseconds>");
      note(args::get(first).count() == 60, "Positional<minutes>");
      auto r = args::get(rest);
      note(r.size() == 2 && r[0].count() == 3 && r[1].count() == 4, "PositionalList<seconds>");
    } catch (const std::exception& e) {
      note(false, std::string("parse throws ") + e.what());
    }
  }
  report("usage");
#elif defined(FAMILY_noexcept)
  // Built with ARGS_NOEXCEPT and -fno-exceptions: errors are reported through GetError().
  {
    args::ArgumentParser parser("probe");
    args::ValueFlag<seconds> flag(parser, "DUR", "", {"dur"});
    args::ValueFlagList<milliseconds> list(parser, "LIST", "", {"list"});
    parser.ParseArgs(std::vector<std::string>{"--dur=2min", "--list=1s", "--list=5ms"});
    note(parser.GetError() == args::Error::None && args::get(flag).count() == 120
         && args::get(list).size() == 2 && args::get(list)[0].count() == 1000, "valid values parse");
    const char* bad[] = {"--dur=1500ms", "--dur=5", "--dur=5sec", "--dur=99999999999999999999s"};
    for (const char* arg : bad) {
      parser.ParseArgs(std::vector<std::string>{arg});
      note(parser.GetError() == args::Error::Parse, std::string(arg) + " does not set Error::Parse");
    }
    parser.ParseArgs(std::vector<std::string>{"--list=1s", "--list=1500us"});
    note(parser.GetError() == args::Error::Parse, "--list=1500us does not set Error::Parse");
  }
  report("noexcept");
#else
#error "define FAMILY_<name>"
#endif
  return 0;
}
