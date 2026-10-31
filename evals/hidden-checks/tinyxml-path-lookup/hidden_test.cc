// Behavior probe for TiXmlNode::FirstChildElementByPath.
#include "tinyxml.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <new>

namespace {

long g_allocations = 0;
int g_failures = 0;

void Expect(bool condition, const char* name) {
  printf("%s %s\n", condition ? "PASS" : "FAIL", name);
  if (!condition) ++g_failures;
}

const char kXml[] =
    "<root>"
    "<!-- comment --><config>text<server><port>80</port></server>"
    "<server><port>81</port><host>h</host></server></config>"
    "<ab><x>in-ab</x></ab><a><y>first-a</y></a><a><x>second-a</x></a>"
    "<ns:item>namespaced</ns:item>"
    "</root>";

const char* Text(const TiXmlElement* element) { return element ? element->GetText() : 0; }

bool TextIs(const TiXmlElement* element, const char* text) {
  const char* actual = Text(element);
  return actual && strcmp(actual, text) == 0;
}

}  // namespace

void* operator new(size_t size) {
  ++g_allocations;
  void* p = malloc(size ? size : 1);
  if (!p) abort();
  return p;
}
void* operator new[](size_t size) { return operator new(size); }
void operator delete(void* p) throw() { free(p); }
void operator delete[](void* p) throw() { free(p); }
void operator delete(void* p, size_t) throw() { free(p); }
void operator delete[](void* p, size_t) throw() { free(p); }

int main() {
  TiXmlDocument doc;
  doc.Parse(kXml);
  if (doc.Error()) {
    printf("FAIL fixture document does not parse: %s\n", doc.ErrorDesc());
    return 1;
  }
  const TiXmlNode& cdoc = doc;
  const TiXmlElement* root = cdoc.FirstChildElementByPath("root");
  Expect(root && strcmp(root->Value(), "root") == 0, "single segment from the document");
  Expect(TextIs(cdoc.FirstChildElementByPath("root/config/server/port"), "80"), "nested path takes first match per level");
  Expect(cdoc.FirstChildElementByPath("root/config/server/host") == 0, "no backtracking into later siblings (server/host)");
  Expect(cdoc.FirstChildElementByPath("root/a/x") == 0, "no backtracking into later siblings (a/x)");
  Expect(TextIs(cdoc.FirstChildElementByPath("root/a/y"), "first-a"), "segment a does not match element ab");
  Expect(TextIs(cdoc.FirstChildElementByPath("root/ab/x"), "in-ab"), "segment ab matches element ab");
  Expect(cdoc.FirstChildElementByPath("roo") == 0 && cdoc.FirstChildElementByPath("rootx") == 0, "prefix or extension of a name does not match");
  Expect(cdoc.FirstChildElementByPath("root/abc") == 0, "missing element");
  Expect(TextIs(cdoc.FirstChildElementByPath("root/ns:item"), "namespaced"), "names with a colon");
  Expect(cdoc.FirstChildElementByPath("") == 0, "empty path");
  Expect(cdoc.FirstChildElementByPath(0) == 0, "NULL path");
  Expect(cdoc.FirstChildElementByPath("/root") == 0, "leading slash");
  Expect(cdoc.FirstChildElementByPath("root/") == 0, "trailing slash");
  Expect(cdoc.FirstChildElementByPath("root//config") == 0, "empty middle segment");
  Expect(cdoc.FirstChildElementByPath("/") == 0 && cdoc.FirstChildElementByPath("//") == 0, "slashes only");
  Expect(root && TextIs(root->FirstChildElementByPath("config/server/port"), "80"), "relative to an element");
  Expect(root && root->FirstChildElementByPath("root") == 0, "path does not include the starting node");

  TiXmlElement* mutable_port = doc.FirstChildElementByPath("root/config/server/port");
  Expect(mutable_port && mutable_port == cdoc.FirstChildElementByPath("root/config/server/port"),
         "non-const overload returns the same element");
  if (mutable_port) mutable_port->SetAttribute("seen", 1);

  TiXmlNode* text_node = 0;
  if (const TiXmlElement* config = cdoc.FirstChildElementByPath("root/config")) text_node = const_cast<TiXmlNode*>(config->FirstChild());
  Expect(text_node && text_node->ToText() && text_node->FirstChildElementByPath("x") == 0, "lookup from a text node finds nothing");

  long before = g_allocations;
  for (int i = 0; i < 100; ++i) cdoc.FirstChildElementByPath("root/config/server/port");
  printf("%s lookup allocates %ld times per call\n", g_allocations == before ? "HIT" : "MISS", (g_allocations - before) / 100);

  return g_failures == 0 ? 0 : 1;
}
