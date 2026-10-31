/* Reviewer-only probe for the minini-number-defaults fixture.
 *
 *   hidden_test getl|getf <dir>   strict conversion cases for one getter family
 *   hidden_test golden <dir>      output of the APIs that must not change, for comparison
 *
 * The probe writes its own INI file into <dir>. Quoted values keep their surrounding spaces.
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "minIni.h"

#define DEF_L 4242L
#define DEF_F 42.5f

enum { VALID, INVALID, EITHER };
typedef struct { const char *key, *line, *value; int kind; double expected; } Case;

static const Case kLong[] = {
  {"dec", "12", "12", VALID, 12}, {"neg", "-7", "-7", VALID, -7}, {"zero", "0", "0", VALID, 0},
  {"lead0", "007", "007", VALID, 7}, {"ten", "010", "010", VALID, 10}, {"hex", "0x1F", "0x1F", VALID, 31},
  {"hexupper", "0X1f", "0X1f", VALID, 31}, {"hexff", "0xff", "0xff", VALID, 255},
  {"spaced", "\" 12 \"", " 12 ", VALID, 12}, {"tabbed", "\"\t-3\t\"", "\t-3\t", VALID, -3},
  {"spacedhex", "\" 0x1F \"", " 0x1F ", VALID, 31},
#if LONG_MAX == 9223372036854775807L
  {"max", "9223372036854775807", "9223372036854775807", VALID, 0},
  {"min", "-9223372036854775808", "-9223372036854775808", VALID, 0},
  {"over", "9223372036854775808", "9223372036854775808", INVALID, 0},
  {"under", "-9223372036854775809", "-9223372036854775809", INVALID, 0},
  {"hexover", "0x10000000000000000", "0x10000000000000000", INVALID, 0},
#endif
  {"alpha", "abc", "abc", INVALID, 0}, {"suffix", "12abc", "12abc", INVALID, 0},
  {"fraction", "1.5", "1.5", INVALID, 0}, {"minus", "-", "-", INVALID, 0}, {"plus", "+", "+", INVALID, 0},
  {"hexprefix", "0x", "0x", INVALID, 0}, {"hexbad", "0x1G", "0x1G", INVALID, 0},
  {"inner", "12 34", "12 34", INVALID, 0}, {"exponent", "1e3", "1e3", INVALID, 0},
  {"empty", "", "", INVALID, 0}, {"quotedempty", "\"\"", "", INVALID, 0}, {"blank", "\"   \"", "   ", INVALID, 0},
  {"plusfive", "+5", "+5", EITHER, 5}, {"neghex", "-0x10", "-0x10", EITHER, -16},
};

static const Case kReal[] = {
  {"frac", "1.5", "1.5", VALID, 1.5}, {"negfrac", "-2.25", "-2.25", VALID, -2.25}, {"int", "3", "3", VALID, 3},
  {"exp", "1e3", "1e3", VALID, 1000}, {"negexp", "2.5e-1", "2.5e-1", VALID, 0.25},
  {"spaced", "\" 1.5 \"", " 1.5 ", VALID, 1.5}, {"big", "3.4e38", "3.4e38", VALID, 3.4e38}, {"zero", "0", "0", VALID, 0},
  {"alpha", "abc", "abc", INVALID, 0}, {"suffix", "1.5x", "1.5x", INVALID, 0}, {"comma", "1,5", "1,5", INVALID, 0},
  {"empty", "", "", INVALID, 0}, {"overflow", "1e39", "1e39", INVALID, 0}, {"negoverflow", "-1e39", "-1e39", INVALID, 0},
  {"twodots", "1.5.2", "1.5.2", INVALID, 0}, {"bareexp", "e5", "e5", INVALID, 0}, {"minus", "-", "-", INVALID, 0},
  {"blank", "\"   \"", "   ", INVALID, 0},
  {"nan", "nan", "nan", EITHER, 0}, {"inf", "inf", "inf", EITHER, 0}, {"leadingdot", ".5", ".5", EITHER, 0.5},
  {"trailingdot", "5.", "5.", EITHER, 5}, {"underflow", "1e-50", "1e-50", EITHER, 0}, {"hexfloat", "0x1p3", "0x1p3", EITHER, 8},
};

static const char *kBool[] = {"yes", "no", "true", "false", "1", "0", "Yonder", "nope", "2", "1abc", "0x1", "T",
                              "f", "maybe", "\" yes\"", ""};

static void write_cases(const char *path, const Case *cases, size_t n) {
  FILE *f = fopen(path, "w");
  size_t i;
  if (!f) { perror(path); exit(2); }
  fprintf(f, "[n]\n");
  for (i = 0; i < n; i++) fprintf(f, "%s=%s\n", cases[i].key, cases[i].line);
  fclose(f);
}

static int setup_ok(const char *path, const Case *c) {
  char raw[128];
  ini_gets("n", c->key, "<missing>", raw, (int)sizeof raw, path);
  if (strcmp(raw, c->value) != 0) {
    printf("FAIL setup: ini_gets returns \"%s\" for %s, expected \"%s\"\n", raw, c->key, c->value);
    return 0;
  }
  return 1;
}

static int check_long(const char *dir) {
  char path[1024], failures[2048] = "", either[512] = "";
  size_t i, n = sizeof kLong / sizeof kLong[0];
  long missing;
  snprintf(path, sizeof path, "%s/getl.ini", dir);
  write_cases(path, kLong, n);
  for (i = 0; i < n; i++) {
    const Case *c = &kLong[i];
    long expected = c->kind == INVALID ? DEF_L : (long)c->expected, got;
    char item[160];
    if (!setup_ok(path, c)) return 1;
#if LONG_MAX == 9223372036854775807L
    if (strcmp(c->key, "max") == 0) expected = LONG_MAX;
    if (strcmp(c->key, "min") == 0) expected = LONG_MIN;
#endif
    got = ini_getl("n", c->key, DEF_L, path);
    if (c->kind == EITHER) {
      snprintf(item, sizeof item, ", \"%s\" -> %ld", c->value, got);
      strcat(either, item);
    } else if (got != expected) {
      snprintf(item, sizeof item, ", \"%s\" -> %ld (want %ld)", c->value, got, expected);
      strcat(failures, item);
    }
  }
  missing = ini_getl("n", "absent", DEF_L, path);
  if (missing != DEF_L) strcat(failures, ", missing key");
  if (*failures) printf("FAIL getl conversion: %s\n", failures + 2);
  else printf("PASS getl conversion: whole-value decimal and hex, DefValue otherwise\n");
  printf("INFO getl undecided inputs: %s\n", either + 2);
  return *failures != 0;
}

static int check_real(const char *dir) {
#if defined INI_REAL
  char path[1024], failures[2048] = "", either[512] = "";
  size_t i, n = sizeof kReal / sizeof kReal[0];
  snprintf(path, sizeof path, "%s/getf.ini", dir);
  write_cases(path, kReal, n);
  for (i = 0; i < n; i++) {
    const Case *c = &kReal[i];
    INI_REAL expected = c->kind == INVALID ? DEF_F : (INI_REAL)c->expected, got;
    char item[160];
    if (!setup_ok(path, c)) return 1;
    got = ini_getf("n", c->key, DEF_F, path);
    if (c->kind == EITHER) {
      snprintf(item, sizeof item, ", \"%s\" -> %.9g", c->value, (double)got);
      strcat(either, item);
    } else if (got != expected) {
      snprintf(item, sizeof item, ", \"%s\" -> %.9g (want %.9g)", c->value, (double)got, (double)expected);
      strcat(failures, item);
    }
  }
  if (ini_getf("n", "absent", DEF_F, path) != DEF_F) strcat(failures, ", missing key");
  if (*failures) printf("FAIL getf conversion: %s\n", failures + 2);
  else printf("PASS getf conversion: whole-value numbers in range, DefValue otherwise\n");
  printf("INFO getf undecided inputs: %s\n", either + 2);
  return *failures != 0;
#else
  (void)dir;
  printf("FAIL getf conversion: INI_REAL is not defined\n");
  return 1;
#endif
}

static int print_entry(const char *section, const char *key, const char *value, void *user) {
  (void)user;
  printf("browse [%s] %s=%s\n", section, key, value);
  return 1;
}

static int golden(const char *dir) {
  char path[1024], buf[128], section[64];
  size_t i;
  int s, k;
  FILE *f;
  snprintf(path, sizeof path, "%s/golden.ini", dir);
  f = fopen(path, "w");
  if (!f) { perror(path); return 2; }
  fprintf(f, "top=1\n[b]\n");
  for (i = 0; i < sizeof kBool / sizeof kBool[0]; i++) fprintf(f, "k%lu=%s\n", (unsigned long)i, kBool[i]);
  fprintf(f, "[l]\n");
  for (i = 0; i < sizeof kLong / sizeof kLong[0]; i++) fprintf(f, "%s=%s ; note\n", kLong[i].key, kLong[i].line);
  fclose(f);
  for (i = 0; i < sizeof kBool / sizeof kBool[0]; i++) {
    char key[16];
    snprintf(key, sizeof key, "k%lu", (unsigned long)i);
    printf("getbool %s=%d\n", key, ini_getbool("b", key, -1, path));
    printf("gets %s=%d:%s\n", key, ini_gets("b", key, "dflt", buf, (int)sizeof buf, path), buf);
  }
  for (i = 0; i < sizeof kLong / sizeof kLong[0]; i++) {
    printf("gets l.%s=%d:%s\n", kLong[i].key, ini_gets("l", kLong[i].key, "dflt", buf, (int)sizeof buf, path), buf);
  }
  printf("gets short=%d:%s\n", ini_gets("l", "suffix", "dflt", buf, 3, path), buf);
  for (s = 0; ini_getsection(s, section, (int)sizeof section, path) > 0; s++) {
    printf("section %s\n", section);
    for (k = 0; ini_getkey(section, k, buf, (int)sizeof buf, path) > 0; k++) printf("  key %s\n", buf);
  }
  printf("haskey %d %d\n", ini_haskey("b", "k1", path), ini_haskey("b", "zz", path));
  ini_browse(print_entry, NULL, path);
  printf("putl %d\n", ini_putl("w", "l", -123, path));
  printf("putf %d\n", ini_putf("w", "f", 1.5f, path));
  printf("puts %d\n", ini_puts("w", "s", "a;b", path));
  printf("putbool %d\n", ini_putbool("w", "b", 1, path));
  printf("delete %d\n", ini_puts("b", "k3", NULL, path));
  f = fopen(path, "rb");
  if (f) {
    int ch;
    printf("file:\n");
    while ((ch = fgetc(f)) != EOF) putchar(ch);
    fclose(f);
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 3 && strcmp(argv[1], "getl") == 0) return check_long(argv[2]);
  if (argc == 3 && strcmp(argv[1], "getf") == 0) return check_real(argv[2]);
  if (argc == 3 && strcmp(argv[1], "golden") == 0) return golden(argv[2]);
  fprintf(stderr, "usage: %s getl|getf|golden <dir>\n", argv[0]);
  return 2;
}
