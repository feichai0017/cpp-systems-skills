/* Reviewer-only probe for the stb-write-errors fixture.
 *
 *   hidden_test faults        every file entry point under injected write failures
 *   hidden_test dump <dir>    writes each format's output for comparison with the original
 *
 * Files named "mem:..." are memory streams (funopen/fopencookie) whose writes or close
 * can be made to fail; "fail-open" makes fopen fail. The writer itself is unmodified.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  unsigned char *data;
  size_t size, cap;
  long limit;      /* bytes accepted before writes fail; -1 = unlimited */
  int fail_close;
} MemStream;

static MemStream g_stream;
static long g_limit = -1;
static int g_fail_close;
static int g_opened, g_closed;

static int mem_write(void *cookie, const char *buf, int n) {
  MemStream *s = (MemStream *)cookie;
  if (s->limit >= 0 && (long)s->size + n > s->limit) {
    long room = s->limit - (long)s->size;
    if (room <= 0) { errno = ENOSPC; return -1; }
    n = (int)room;
  }
  if (s->size + n > s->cap) {
    size_t cap = s->cap ? s->cap * 2 : 4096;
    while (cap < s->size + n) cap *= 2;
    s->data = (unsigned char *)realloc(s->data, cap);
    s->cap = cap;
  }
  memcpy(s->data + s->size, buf, n);
  s->size += n;
  return n;
}

static int mem_close(void *cookie) {
  MemStream *s = (MemStream *)cookie;
  g_closed++;
  if (s->fail_close) { errno = EIO; return -1; }
  return 0;
}

#ifdef __APPLE__
static FILE *open_mem(MemStream *s) { return funopen(s, 0, mem_write, 0, mem_close); }
#else
static ssize_t mem_write_thunk(void *c, const char *b, size_t n) { return mem_write(c, b, (int)n); }
static FILE *open_mem(MemStream *s) {
  cookie_io_functions_t io = {0, mem_write_thunk, 0, mem_close};
  return fopencookie(s, "w", io);
}
#endif

static FILE *test_fopen(const char *name, const char *mode) {
  if (strcmp(name, "fail-open") == 0) { errno = ENOSPC; return NULL; }
  if (strncmp(name, "mem:", 4) == 0) {
    free(g_stream.data);
    memset(&g_stream, 0, sizeof g_stream);
    g_stream.limit = g_limit;
    g_stream.fail_close = g_fail_close;
    g_opened++;
    return open_mem(&g_stream);
  }
  return fopen(name, mode);
}

#define fopen test_fopen
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#undef fopen

enum { W = 64, H = 48 };
static unsigned char g_rgb[W * H * 3];
static float g_hdr[W * H * 3];

static void make_image(void) {
  unsigned int x = 12345u;
  int i;
  for (i = 0; i < W * H * 3; i++) {
    x = x * 1103515245u + 12345u;
    g_rgb[i] = (unsigned char)(x >> 16);
    g_hdr[i] = (float)(x >> 8 & 0xffff) / 4096.0f;
  }
}

typedef struct { const char *name; int (*write_file)(const char *); int (*write_func)(stbi_write_func *, void *); } Format;

static int png_file(const char *f) { return stbi_write_png(f, W, H, 3, g_rgb, W * 3); }
static int bmp_file(const char *f) { return stbi_write_bmp(f, W, H, 3, g_rgb); }
static int tga_file(const char *f) { stbi_write_tga_with_rle = 1; return stbi_write_tga(f, W, H, 3, g_rgb); }
static int tga_raw_file(const char *f) { int r; stbi_write_tga_with_rle = 0; r = stbi_write_tga(f, W, H, 3, g_rgb); stbi_write_tga_with_rle = 1; return r; }
static int hdr_file(const char *f) { return stbi_write_hdr(f, W, H, 3, g_hdr); }
static int jpg_file(const char *f) { return stbi_write_jpg(f, W, H, 3, g_rgb, 90); }
static int png_func(stbi_write_func *fn, void *c) { return stbi_write_png_to_func(fn, c, W, H, 3, g_rgb, W * 3); }
static int bmp_func(stbi_write_func *fn, void *c) { return stbi_write_bmp_to_func(fn, c, W, H, 3, g_rgb); }
static int tga_func(stbi_write_func *fn, void *c) { stbi_write_tga_with_rle = 1; return stbi_write_tga_to_func(fn, c, W, H, 3, g_rgb); }
static int tga_raw_func(stbi_write_func *fn, void *c) { int r; stbi_write_tga_with_rle = 0; r = stbi_write_tga_to_func(fn, c, W, H, 3, g_rgb); stbi_write_tga_with_rle = 1; return r; }
static int hdr_func(stbi_write_func *fn, void *c) { return stbi_write_hdr_to_func(fn, c, W, H, 3, g_hdr); }
static int jpg_func(stbi_write_func *fn, void *c) { return stbi_write_jpg_to_func(fn, c, W, H, 3, g_rgb, 90); }

static const Format kFormats[] = {
  {"png", png_file, png_func}, {"bmp", bmp_file, bmp_func}, {"tga", tga_file, tga_func},
  {"tga-raw", tga_raw_file, tga_raw_func}, {"hdr", hdr_file, hdr_func}, {"jpg", jpg_file, jpg_func},
};

typedef struct { unsigned char *data; size_t size; } Buffer;

static void collect(void *context, void *data, int size) {
  Buffer *b = (Buffer *)context;
  b->data = (unsigned char *)realloc(b->data, b->size + size);
  memcpy(b->data + b->size, data, size);
  b->size += size;
}

static int write_with(const Format *f, long limit, int fail_close, const char *name) {
  int r;
  g_limit = limit;
  g_fail_close = fail_close;
  g_opened = g_closed = 0;
  r = f->write_file(name);
  g_limit = -1;
  g_fail_close = 0;
  return r;
}

static int run_faults(void) {
  size_t i;
  int failed = 0;
  for (i = 0; i < sizeof kFormats / sizeof kFormats[0]; i++) {
    const Format *f = &kFormats[i];
    Buffer expected = {0, 0};
    char problems[512] = "";
    char leaks[256] = "";
    int r;
    struct { const char *label; long limit; int fail_close; } faults[4];
    int k;

    f->write_func(collect, &expected);
    faults[0].label = "every write fails"; faults[0].limit = 0; faults[0].fail_close = 0;
    faults[1].label = "writes fail halfway"; faults[1].limit = (long)expected.size / 2; faults[1].fail_close = 0;
    faults[2].label = "the last byte fails"; faults[2].limit = (long)expected.size - 1; faults[2].fail_close = 0;
    faults[3].label = "fclose fails"; faults[3].limit = -1; faults[3].fail_close = 1;

    r = write_with(f, -1, 0, "fail-open");
    if (r != 0) strcat(problems, ", fopen fails");
    for (k = 0; k < 4; k++) {
      r = write_with(f, faults[k].limit, faults[k].fail_close, "mem:out");
      if (r != 0) { strcat(problems, ", "); strcat(problems, faults[k].label); }
      if (g_closed != g_opened) { strcat(leaks, ", "); strcat(leaks, faults[k].label); }
    }
    if (*problems) { printf("FAIL %s write failures: returns non-zero when %s\n", f->name, problems + 2); failed = 1; }
    else printf("PASS %s write failures return 0\n", f->name);
    if (*leaks) { printf("FAIL %s file handling: FILE not closed exactly once when %s\n", f->name, leaks + 2); failed = 1; }
    else printf("PASS %s file handling: FILE closed once on every failure\n", f->name);

    r = write_with(f, -1, 0, "mem:out");
    if (r == 0 || g_stream.size != expected.size || memcmp(g_stream.data, expected.data, expected.size) != 0) {
      printf("FAIL %s success path: returns %d, writes %lu bytes (callback variant writes %lu)\n", f->name, r,
             (unsigned long)g_stream.size, (unsigned long)expected.size);
      failed = 1;
    } else {
      printf("PASS %s success path returns non-zero with complete output\n", f->name);
    }
    free(expected.data);
  }
  free(g_stream.data);
  return failed;
}

static void save(const char *dir, const char *name, const unsigned char *data, size_t size) {
  char path[1024];
  FILE *out;
  snprintf(path, sizeof path, "%s/%s", dir, name);
  out = fopen(path, "wb");
  if (!out) { perror(path); exit(2); }
  fwrite(data, 1, size, out);
  fclose(out);
}

static int run_dump(const char *dir) {
  size_t i;
  for (i = 0; i < sizeof kFormats / sizeof kFormats[0]; i++) {
    const Format *f = &kFormats[i];
    Buffer callback = {0, 0};
    char name[64];
    int r = f->write_func(collect, &callback);
    snprintf(name, sizeof name, "%s.func.%d", f->name, r);
    save(dir, name, callback.data, callback.size);
    r = write_with(f, -1, 0, "mem:out");
    snprintf(name, sizeof name, "%s.file.%d", f->name, r != 0);
    save(dir, name, g_stream.data, g_stream.size);
    free(callback.data);
  }
  {
    int len = 0;
    unsigned char *png = stbi_write_png_to_mem(g_rgb, W * 3, W, H, 3, &len);
    save(dir, "png.mem", png, (size_t)len);
    STBIW_FREE(png);
  }
  free(g_stream.data);
  return 0;
}

int main(int argc, char **argv) {
  make_image();
  if (argc >= 2 && strcmp(argv[1], "faults") == 0) return run_faults();
  if (argc >= 3 && strcmp(argv[1], "dump") == 0) return run_dump(argv[2]);
  fprintf(stderr, "usage: %s faults | dump <dir>\n", argv[0]);
  return 2;
}
