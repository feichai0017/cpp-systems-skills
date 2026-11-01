/* Reviewer-only behavior probe for jsmn-find-key. Each case gives jsmn_find a token
 * array of exactly the parsed count, so reading past count is caught by ASan.
 * Prints one PASS/FAIL line and exits 0. */
#include "jsmn.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct find_case {
  const char *json;
  int object;
  const char *key;
  int expected;
};

static const struct find_case cases[] = {
    {"{\"a\":0}", 0, "a", 2},
    {"{\"a\":0}", 0, "b", -1},
    {"{\"a\":0,\"b\":\"c\"}", 0, "b", 4},
    /* only direct members */
    {"{\"a\":{\"x\":1},\"b\":2}", 0, "b", 6},
    {"{\"a\":{\"x\":1},\"b\":2}", 0, "x", -1},
    {"{\"a\":{\"x\":1},\"b\":2}", 2, "x", 4},
    {"{\"a\":[1,{\"b\":2}],\"c\":3}", 0, "c", 8},
    {"{\"a\":[1,{\"b\":2}],\"c\":3}", 0, "b", -1},
    {"{\"a\":[1,{\"b\":2}],\"c\":3}", 4, "b", 6},
    {"{\"x\":[[[{\"y\":1}]]],\"y\":2}", 0, "y", 9},
    /* first of duplicate keys */
    {"{\"k\":1,\"k\":2}", 0, "k", 2},
    /* whole-key comparison */
    {"{\"ab\":1,\"a\":2}", 0, "a", 4},
    {"{\"ab\":1,\"a\":2}", 0, "abc", -1},
    {"{\"ab\":1,\"a\":2}", 0, "", -1},
    {"{\"\":1}", 0, "", 2},
    /* raw bytes, no unescaping */
    {"{\"a\\\"b\":1}", 0, "a\\\"b", 2},
    {"{\"a\\\"b\":1}", 0, "a\"b", -1},
    /* key-like text inside a string value */
    {"{\"a\":\"\\\"b\\\":1\",\"b\":2}", 0, "b", 4},
    /* not an object */
    {"[1,2]", 0, "a", -1},
    {"{\"a\":\"x\"}", 2, "a", -1},
    {"{\"a\":[]}", 2, "a", -1},
    /* keys without values */
    {"{\"a\"}", 0, "a", -1},
    {"{\"a\":1,\"b\"}", 0, "b", -1},
    {"{\"a\":1,\"b\"}", 0, "a", 2},
    /* objects inside arrays, and not running into the next sibling */
    {"[{\"a\":1},{\"a\":2}]", 1, "a", 3},
    {"[{\"a\":1},{\"a\":2}]", 4, "a", 6},
    {"[{},{\"a\":1}]", 1, "a", -1},
    {"[{\"b\":1},{\"a\":1}]", 1, "a", -1},
    {"{}", 0, "a", -1},
};

int main(void) {
  int failures = 0;
  size_t i;
  char first[200] = "";
  for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
    const struct find_case *c = &cases[i];
    jsmn_parser parser;
    jsmntok_t *tokens;
    int count, found;
    jsmn_init(&parser);
    count = jsmn_parse(&parser, c->json, strlen(c->json), NULL, 0);
    tokens = (jsmntok_t *)malloc(sizeof(jsmntok_t) * (size_t)count);
    jsmn_init(&parser);
    if (jsmn_parse(&parser, c->json, strlen(c->json), tokens, (unsigned)count) != count) {
      printf("FAIL find: setup could not parse %s\n", c->json);
      return 0;
    }
    found = jsmn_find(c->json, tokens, count, c->object, c->key);
    if (found != c->expected && failures++ == 0) {
      snprintf(first, sizeof first, "%s object %d key \"%s\" gives %d, expected %d", c->json,
               c->object, c->key, found, c->expected);
    }
    free(tokens);
  }
  if (failures == 0) {
    printf("PASS find\n");
  } else {
    printf("FAIL find: %d case(s), first: %s\n", failures, first);
  }
  return 0;
}
