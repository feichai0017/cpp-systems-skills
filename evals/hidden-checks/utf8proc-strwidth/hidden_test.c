/* Reviewer-only behavior probe for utf8proc-strwidth. Strings with an explicit length are
 * copied into buffers of exactly that size with no NUL after them, so reading past strlen is
 * caught by ASan. Prints PASS/FAIL lines and exits 0. */
#include "utf8proc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
static char first[200] = "";
static void note(int ok, const char *what) {
    if (!ok && failures++ == 0) snprintf(first, sizeof first, "%s", what);
}
static void report(const char *family) {
    if (failures == 0) printf("PASS strwidth %s\n", family);
    else printf("FAIL strwidth %s: %d case(s), first: %s\n", family, failures, first);
    failures = 0;
    first[0] = '\0';
}

/* Width of exactly len bytes, from a buffer that ends there. */
static utf8proc_ssize_t sized(const char *bytes, size_t len) {
    utf8proc_uint8_t *copy = malloc(len ? len : 1);
    utf8proc_ssize_t width;
    memcpy(copy, bytes, len);
    width = utf8proc_strwidth(copy, (utf8proc_ssize_t)len);
    free(copy);
    return width;
}
static utf8proc_ssize_t terminated(const char *text) {
    return utf8proc_strwidth((const utf8proc_uint8_t *)text, -1);
}
static void expect(const char *label, utf8proc_ssize_t got, utf8proc_ssize_t want) {
    char msg[160];
    snprintf(msg, sizeof msg, "%s gives %ld, expected %ld", label, (long)got, (long)want);
    note(got == want, msg);
}

int main(void) {
    const utf8proc_ssize_t bad = UTF8PROC_ERROR_INVALIDUTF8;
    utf8proc_int32_t c;
    unsigned seed = 12345;
    int round;

    expect("abc", terminated("abc"), 3);
    expect("abc, 3 bytes", sized("abc", 3), 3);
    expect("abc, 2 bytes", sized("abc", 2), 2);
    expect("CJK", terminated("\xe4\xb8\xad\xe6\x96\x87"), 4);
    expect("combining acute", terminated("e\xcc\x81"), 1);
    expect("controls", terminated("\t\n\x7f"), 0);
    expect("emoji", terminated("\xf0\x9f\x98\x80"), 2);
    expect("empty, NUL-terminated", terminated(""), 0);
    expect("empty, 0 bytes", sized("", 0), 0);
    expect("NUL inside 3 bytes", sized("a\0b", 3), 2);
    expect("stops at NUL", terminated("a\0b"), 1);
    report("results");

    expect("truncated 3-byte sequence, 2 bytes", sized("\xe4\xb8", 2), bad);
    expect("truncated 3-byte sequence before NUL", terminated("\xe4\xb8"), bad);
    expect("prefix cut inside a sequence", sized("a\xe4\xb8\xad", 3), bad);
    expect("0xff", sized("\xff", 1), bad);
    expect("overlong NUL", sized("\xc0\x80", 2), bad);
    expect("surrogate", sized("\xed\xa0\x80", 3), bad);
    expect("lone continuation", terminated("\x80"), bad);
    expect("invalid after valid text", terminated("ab\xe4\xb8\xad\xff"), bad);
    report("invalid");

    for (c = 1; c <= 0x10FFFF; c++) {
        utf8proc_uint8_t buf[5];
        utf8proc_ssize_t n;
        char msg[80];
        if (c >= 0xD800 && c <= 0xDFFF) continue;
        n = utf8proc_encode_char(c, buf);
        buf[n] = 0;
        snprintf(msg, sizeof msg, "U+%04X", (unsigned)c);
        if (utf8proc_strwidth(buf, n) != utf8proc_charwidth(c) || utf8proc_strwidth(buf, -1) != utf8proc_charwidth(c))
            note(0, msg);
    }
    report("every codepoint");

    for (round = 0; round < 2000; round++) {
        utf8proc_uint8_t buf[4 * 64 + 1];
        utf8proc_ssize_t len = 0, want = 0;
        int k, count = (int)(seed % 64);
        for (k = 0; k < count; k++) {
            seed = seed * 1103515245u + 12345u;
            c = (utf8proc_int32_t)(seed % 0x10FFFF) + 1;
            if (c >= 0xD800 && c <= 0xDFFF) c -= 0x800;
            len += utf8proc_encode_char(c, buf + len);
            want += utf8proc_charwidth(c);
        }
        buf[len] = 0;
        seed = seed * 1103515245u + 12345u;
        if (utf8proc_strwidth(buf, -1) != want) note(0, "random NUL-terminated string");
        if (sized((const char *)buf, (size_t)len) != want) note(0, "random string with its length");
    }
    report("random");
    return 0;
}
