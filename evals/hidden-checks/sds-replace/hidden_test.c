/* Reviewer-only behavior probe for sds-replace. Builds against the workspace's sds.c with a
 * counting allocator (sdsalloc.h) under ASan/UBSan. Prints PASS/FAIL (HIT/MISS for the soft
 * family) and exits 0. */
#include "sds.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static long live = 0;
static long fail_at = 0; /* fail the fail_at-th allocation from now; 0 = never */

static int should_fail(void) { return fail_at > 0 && --fail_at == 0; }
void *probe_malloc(size_t size) {
    void *p;
    if (should_fail()) return NULL;
    p = malloc(size);
    if (p) live++;
    return p;
}
void *probe_realloc(void *ptr, size_t size) {
    void *p;
    if (should_fail()) return NULL;
    p = realloc(ptr, size);
    if (p && !ptr) live++;
    return p;
}
void probe_free(void *ptr) {
    if (ptr) live--;
    free(ptr);
}

static int failures = 0;
static char first[300] = "";
static void note(int ok, const char *what) {
    if (!ok && failures++ == 0) snprintf(first, sizeof first, "%s", what);
}
static void report(const char *family, int soft) {
    if (failures == 0) printf("%s replace %s\n", soft ? "HIT" : "PASS", family);
    else printf("%s replace %s: %d case(s), first: %s\n", soft ? "MISS" : "FAIL", family, failures, first);
    failures = 0;
    first[0] = '\0';
}

/* Naive left-to-right, non-overlapping replacement used as the oracle. */
static size_t oracle(const char *s, size_t len, const char *from, size_t fl, const char *to, size_t tl, char *out) {
    size_t i = 0, j = 0;
    if (fl == 0) { memcpy(out, s, len); return len; }
    while (i < len) {
        if (i + fl <= len && memcmp(s + i, from, fl) == 0) {
            memcpy(out + j, to, tl);
            j += tl;
            i += fl;
        } else {
            out[j++] = s[i++];
        }
    }
    return j;
}

static void check(const char *label, const char *s, size_t len, const char *from, size_t fl, const char *to, size_t tl) {
    char *want = malloc(len * (tl + 1) + 1);
    size_t want_len = oracle(s, len, from, fl, to, tl, want);
    long before = live;
    sds x = sdsnewlen(s, len), r;
    char msg[300];
    r = sdsreplace(x, from, fl, to, tl);
    if (r == NULL) {
        snprintf(msg, sizeof msg, "%s returns NULL", label);
        note(0, msg);
    } else {
        snprintf(msg, sizeof msg, "%s gives %zu bytes, expected %zu", label, sdslen(r), want_len);
        note(sdslen(r) == want_len && memcmp(r, want, want_len) == 0, msg);
        snprintf(msg, sizeof msg, "%s is not NUL-terminated", label);
        note(r[sdslen(r)] == '\0', msg);
        r = sdscatlen(r, "+", 1); /* the result stays a usable sds */
        snprintf(msg, sizeof msg, "%s cannot be appended to", label);
        note(r != NULL && sdslen(r) == want_len + 1 && r[want_len] == '+', msg);
        snprintf(msg, sizeof msg, "%s leaves %ld extra allocation(s)", label, live - before - 1);
        note(live == before + 1, msg);
        sdsfree(r);
    }
    free(want);
}

static char *repeat(const char *unit, size_t unit_len, size_t times) {
    char *p = malloc(unit_len * times + 1);
    size_t i;
    for (i = 0; i < times; i++) memcpy(p + i * unit_len, unit, unit_len);
    return p;
}

int main(void) {
    char *big;
    check("one -> 1", "one two one", 11, "one", 3, "1", 1);
    check("1 -> three", "1 two 1", 7, "1", 1, "three", 5);
    check("no match", "three two three", 15, "xyz", 3, "!", 1);
    check("overlap aaaa", "aaaa", 4, "aa", 2, "b", 1);
    check("overlap aaa", "aaa", 3, "aa", 2, "b", 1);
    check("deletion", "a,b,,c", 6, ",", 1, "", 0);
    check("start and end", "abXab", 5, "ab", 2, "Q", 1);
    check("whole string", "same", 4, "same", 4, "other", 5);
    check("embedded NUL in s and from", "a\0b\0c", 5, "\0", 1, "--", 2);
    check("embedded NUL in to", "a-b", 3, "-", 1, "\0\0", 2);
    check("empty from", "abc", 3, "", 0, "x", 1);
    check("empty s", "", 0, "a", 1, "bb", 2);
    check("from longer than s", "ab", 2, "abc", 3, "x", 1);
    check("to equals from", "abab", 4, "ab", 2, "ab", 2);
    big = repeat("x", 1, 200);
    check("type 8 to 16 header", big, 200, "x", 1, "yy", 2);
    free(big);
    big = repeat("x", 1, 40000);
    check("type 16 to 32 header", big, 40000, "x", 1, "xy", 2);
    free(big);
    big = repeat("abc", 3, 30000);
    check("shrinking 90000 bytes", big, 90000, "abc", 3, "", 0);
    free(big);
    report("results", 0);

    /* Every allocation in a replacement can fail: the call returns NULL or a correct result. */
    {
        long n;
        for (n = 1; n <= 8; n++) {
            sds x = sdsnew("one two one two one"), r;
            char msg[120];
            fail_at = n;
            r = sdsreplace(x, "one", 3, "three", 5);
            fail_at = 0;
            snprintf(msg, sizeof msg, "allocation %ld failing gives a wrong result", n);
            note(r == NULL || (sdslen(r) == 25 && memcmp(r, "three two three two three", 25) == 0), msg);
            if (r) sdsfree(r);
        }
    }
    report("out of memory", 0);

    /* Replacing 150000 occurrences in 300000 bytes stays linear. */
    {
        clock_t start = clock();
        sds x;
        double seconds;
        big = repeat("ab", 2, 150000);
        x = sdsnewlen(big, 300000);
        x = sdsreplace(x, "ab", 2, "xyz", 3);
        seconds = (double)(clock() - start) / CLOCKS_PER_SEC;
        note(x != NULL && sdslen(x) == 450000, "150000 replacements give a wrong length");
        {
            char msg[80];
            snprintf(msg, sizeof msg, "150000 replacements take %.1f s", seconds);
            note(seconds < 2.0, msg);
        }
        sdsfree(x);
        free(big);
    }
    report("linear time", 1);
    return 0;
}
