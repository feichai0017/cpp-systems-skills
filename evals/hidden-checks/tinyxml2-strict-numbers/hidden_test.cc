// Probe for strict numeric conversion in TinyXML-2 attributes and text.
// Each case states the expected outcome; failures must keep the output untouched.
#include "tinyxml2.h"

#include <stdio.h>
#include <string.h>

#include <map>
#include <string>

using namespace tinyxml2;

namespace {

struct Family {
  int cases;
  int failures;
  std::string first_failures;
};
std::map<std::string, Family> g_families;

void Report(const char* family, const char* input, bool ok, const char* detail) {
  Family& f = g_families[family];
  ++f.cases;
  if (!ok) {
    if (f.failures < 3) f.first_failures += std::string(f.failures ? "; " : "") + "\"" + input + "\" " + detail;
    ++f.failures;
  }
}

std::string Attr(const char* value) { return std::string("<e v=\"") + value + "\"/>"; }
std::string Text(const char* value) { return std::string("<e>") + value + "</e>"; }

template <class T>
bool Same(T a, T b) { return a == b; }

// Runs one input through the attribute, XMLAttribute and text entry points.
template <class T, class AttrQuery, class ValueQuery, class TextQuery>
void Check(const char* family, const char* input, bool accept, T expected, T sentinel, AttrQuery attr,
           ValueQuery value, TextQuery text) {
  char detail[160];
  {
    XMLDocument doc;
    doc.Parse(Attr(input).c_str());
    const XMLElement* e = doc.FirstChildElement("e");
    T out = sentinel;
    XMLError err = e ? attr(e, &out) : XML_ERROR_PARSING;
    bool ok = accept ? (err == XML_SUCCESS && Same(out, expected))
                     : (err == XML_WRONG_ATTRIBUTE_TYPE && Same(out, sentinel));
    snprintf(detail, sizeof detail, "attribute returned %d", static_cast<int>(err));
    Report(family, input, ok, detail);
    T out2 = sentinel;
    const XMLAttribute* a = e ? e->FindAttribute("v") : 0;
    err = a ? value(a, &out2) : XML_ERROR_PARSING;
    ok = accept ? (err == XML_SUCCESS && Same(out2, expected)) : (err == XML_WRONG_ATTRIBUTE_TYPE && Same(out2, sentinel));
    snprintf(detail, sizeof detail, "XMLAttribute returned %d", static_cast<int>(err));
    Report(family, input, ok, detail);
  }
  // Whitespace-only element content creates no text node, so only attributes cover it.
  if (strspn(input, " ") != strlen(input)) {
    XMLDocument doc;
    doc.Parse(Text(input).c_str());
    const XMLElement* e = doc.FirstChildElement("e");
    T out = sentinel;
    XMLError err = e ? text(e, &out) : XML_ERROR_PARSING;
    bool ok = accept ? (err == XML_SUCCESS && Same(out, expected))
                     : (err == XML_CAN_NOT_CONVERT_TEXT && Same(out, sentinel));
    snprintf(detail, sizeof detail, "text returned %d", static_cast<int>(err));
    Report(family, input, ok, detail);
  }
}

XMLError IntA(const XMLElement* e, int* v) { return e->QueryIntAttribute("v", v); }
XMLError IntV(const XMLAttribute* a, int* v) { return a->QueryIntValue(v); }
XMLError IntT(const XMLElement* e, int* v) { return e->QueryIntText(v); }
XMLError UnsA(const XMLElement* e, unsigned* v) { return e->QueryUnsignedAttribute("v", v); }
XMLError UnsV(const XMLAttribute* a, unsigned* v) { return a->QueryUnsignedValue(v); }
XMLError UnsT(const XMLElement* e, unsigned* v) { return e->QueryUnsignedText(v); }
XMLError BoolA(const XMLElement* e, bool* v) { return e->QueryBoolAttribute("v", v); }
XMLError BoolV(const XMLAttribute* a, bool* v) { return a->QueryBoolValue(v); }
XMLError BoolT(const XMLElement* e, bool* v) { return e->QueryBoolText(v); }
XMLError DblA(const XMLElement* e, double* v) { return e->QueryDoubleAttribute("v", v); }
XMLError DblV(const XMLAttribute* a, double* v) { return a->QueryDoubleValue(v); }
XMLError DblT(const XMLElement* e, double* v) { return e->QueryDoubleText(v); }
XMLError FltA(const XMLElement* e, float* v) { return e->QueryFloatAttribute("v", v); }
XMLError FltV(const XMLAttribute* a, float* v) { return a->QueryFloatValue(v); }
XMLError FltT(const XMLElement* e, float* v) { return e->QueryFloatText(v); }

void Int(const char* in, bool accept, int expected = 0) { Check("int", in, accept, expected, 4242, IntA, IntV, IntT); }
void Uns(const char* in, bool accept, unsigned expected = 0) { Check("unsigned", in, accept, expected, 4242u, UnsA, UnsV, UnsT); }
void Bool(const char* in, bool accept, bool expected = false) {
  // The sentinel is the opposite of the expected value so an untouched output is visible.
  Check("bool", in, accept, expected, !expected, BoolA, BoolV, BoolT);
}
void Dbl(const char* in, bool accept, double expected = 0) { Check("double", in, accept, expected, 42.5, DblA, DblV, DblT); }
void Flt(const char* in, bool accept, float expected = 0) { Check("float", in, accept, expected, 42.5f, FltA, FltV, FltT); }

}  // namespace

int main() {
  Int("12", true, 12);
  Int(" 12 ", true, 12);
  Int("+5", true, 5);
  Int("-7", true, -7);
  Int("010", true, 10);
  Int("2147483647", true, 2147483647);
  Int("-2147483648", true, -2147483647 - 1);
  Int("2147483648", false);
  Int("-2147483649", false);
  Int("99999999999999999999", false);
  Int("12abc", false);
  Int("12 abc", false);
  Int("abc", false);
  Int("", false);
  Int("   ", false);
  Int("0x10", false);
  Int("2.0", true, 2);  // xmltest.cpp "Query attribute: double as int" keeps this working
  Int("- 5", false);

  Uns("7", true, 7u);
  Uns(" 7 ", true, 7u);
  Uns("+3", true, 3u);
  Uns("4294967295", true, 4294967295u);
  Uns("4294967296", false);
  Uns("-1", false);
  Uns("12abc", false);
  Uns("", false);

  Bool("true", true, true);
  Bool("false", true, false);
  Bool("1", true, true);
  Bool("0", true, false);
  Bool("2", true, true);
  Bool(" 1 ", true, true);
  Bool("1abc", false, true);
  Bool("yes", false, true);

  Dbl("1.5", true, 1.5);
  Dbl(" -2.25 ", true, -2.25);
  Dbl("1e3", true, 1000.0);
  Dbl("12", true, 12.0);
  Dbl("1.5x", false);
  Dbl("abc", false);
  Dbl("", false);
  Dbl("1e999", false);

  Flt("1.5", true, 1.5f);
  Flt(" 2 ", true, 2.0f);
  Flt("3.25e2", true, 325.0f);
  Flt("1e39", false);
  Flt("1.5f", false);

  {
    XMLDocument doc;
    doc.Parse("<e/>");
    int out = 4242;
    XMLError err = doc.FirstChildElement("e")->QueryIntAttribute("missing", &out);
    Report("int", "(missing attribute)", err == XML_NO_ATTRIBUTE && out == 4242, "missing attribute");
    err = doc.FirstChildElement("e")->QueryIntText(&out);
    Report("int", "(no text)", err == XML_NO_TEXT_NODE && out == 4242, "missing text");
  }
  int failures = 0;
  for (std::map<std::string, Family>::const_iterator it = g_families.begin(); it != g_families.end(); ++it) {
    const Family& f = it->second;
    if (f.failures) printf("FAIL %s conversion: %d of %d cases wrong, e.g. %s\n", it->first.c_str(), f.failures, f.cases, f.first_failures.c_str());
    else printf("PASS %s conversion: %d cases\n", it->first.c_str(), f.cases);
    failures += f.failures;
  }
  return failures ? 1 : 0;
}
