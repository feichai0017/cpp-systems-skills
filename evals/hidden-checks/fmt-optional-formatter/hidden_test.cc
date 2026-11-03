// Reviewer-only probe for the fmt-optional-formatter fixture. Compile once per family
// with -DFAMILY=<name> so that a family that does not compile does not hide the others.
// FAMILY=golden prints formatters that exist in the original, for comparison.
#define FMT_HEADER_ONLY
#include "fmt/std.h"
#include "fmt/ranges.h"
#include "fmt/xchar.h"

#include <cstdio>
#include <string>
#include <thread>
#include <variant>
#include <vector>
#if FMT_CPLUSPLUS >= 201703L
#  include <optional>
#  include <string_view>
#endif

static int failures = 0;
static std::string details;

template <typename S>
static void expect(const char* label, const S& got, const S& want) {
  if (got == want) return;
  ++failures;
  details += std::string(", ") + label;
}

#define STR_(x) #x
#define STR(x) STR_(x)

struct NotFormattable {};

int main() {
#if defined(FAMILY_basic)
  expect("42", fmt::format("{}", std::optional<int>(42)), std::string("optional(42)"));
  expect("nullopt", fmt::format("{}", std::optional<int>()), std::string("none"));
  expect("bool", fmt::format("{}", std::optional<bool>(true)), std::string("optional(true)"));
#elif defined(FAMILY_specs)
  expect("{:x}", fmt::format("{:x}", std::optional<int>(255)), std::string("optional(ff)"));
  expect("{:>4}", fmt::format("{:>4}", std::optional<int>(7)), std::string("optional(   7)"));
  expect("{:.2f}", fmt::format("{:.2f}", std::optional<double>(1.5)), std::string("optional(1.50)"));
  std::printf("INFO specs on an empty optional: \"{:x}\" -> %s\n", fmt::format("{:x}", std::optional<int>()).c_str());
#elif defined(FAMILY_strings)
  expect("string", fmt::format("{}", std::optional<std::string>("a\"b")), std::string("optional(\"a\\\"b\")"));
  expect("char", fmt::format("{}", std::optional<char>('x')), std::string("optional('x')"));
  expect("string_view", fmt::format("{}", std::optional<std::string_view>("sv")), std::string("optional(\"sv\")"));
  expect("newline", fmt::format("{}", std::optional<std::string>("a\nb")), std::string("optional(\"a\\nb\")"));
#elif defined(FAMILY_nested)
  expect("optional<optional>", fmt::format("{}", std::optional<std::optional<int>>(std::optional<int>(1))),
         std::string("optional(optional(1))"));
  expect("optional<empty optional>", fmt::format("{}", std::optional<std::optional<int>>(std::optional<int>())),
         std::string("optional(none)"));
  expect("optional<vector>", fmt::format("{}", std::optional<std::vector<int>>(std::vector<int>{1, 2})),
         std::string("optional([1, 2])"));
  expect("vector<optional>", fmt::format("{}", std::vector<std::optional<int>>{1, std::nullopt}),
         std::string("[optional(1), none]"));
#elif defined(FAMILY_wchar)
  expect("L int", fmt::format(L"{}", std::optional<int>(1)), std::wstring(L"optional(1)"));
  expect("L nullopt", fmt::format(L"{}", std::optional<int>()), std::wstring(L"none"));
  expect("L wstring", fmt::format(L"{}", std::optional<std::wstring>(L"a")), std::wstring(L"optional(\"a\")"));
  expect("L {:x}", fmt::format(L"{:x}", std::optional<int>(255)), std::wstring(L"optional(ff)"));
#elif defined(FAMILY_constraint)
  if (fmt::is_formattable<std::optional<NotFormattable>>::value) { ++failures; details += ", optional<NotFormattable> is formattable"; }
  if (!fmt::is_formattable<std::optional<int>>::value) { ++failures; details += ", optional<int> is not formattable"; }
  if (!fmt::is_formattable<std::optional<int>, wchar_t>::value) { ++failures; details += ", optional<int> is not formattable for wchar_t"; }
#elif defined(FAMILY_golden)
  std::printf("%s\n", fmt::format("{}", std::variant<int, std::string, char>(1)).c_str());
  std::printf("%s\n", fmt::format("{}", std::variant<int, std::string, char>(std::string("a\"b"))).c_str());
  std::printf("%s\n", fmt::format("{}", std::variant<int, std::string, char>('c')).c_str());
  std::printf("%s\n", fmt::format("{}", std::variant<std::monostate, int>()).c_str());
  std::printf("%s\n", fmt::format("{}", std::vector<std::variant<int, std::string>>{1, std::string("x")}).c_str());
  std::printf("%d\n", static_cast<int>(fmt::format("{}", std::this_thread::get_id()).empty()));
  return 0;
#else
#  error "define FAMILY_<name>"
#endif
  if (failures == 0) {
    std::printf("PASS optional %s\n", STR(FAMILY_NAME));
    return 0;
  }
  std::printf("FAIL optional %s: %s\n", STR(FAMILY_NAME), details.c_str() + 2);
  return 1;
}
