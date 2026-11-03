// Probe for the lodepng C++ wrapper. Built with -DLODEPNG_NO_COMPILE_ALLOCATORS so
// this file owns lodepng_malloc/realloc/free and the global operator new.
// "golden" lines must match the imported original; "PASS"/"FAIL" lines check
// that std::bad_alloc thrown at any allocation leaks neither C buffers nor files.
#include "lodepng.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <new>
#include <string>
#include <vector>

namespace {

long g_live = 0;        // lodepng_malloc buffers not yet released
long g_countdown = -1;  // operator new calls left before one throws; -1 disables

std::string g_dir;
std::vector<unsigned char> g_image;
std::vector<unsigned char> g_png;
std::vector<unsigned char> g_zlib;
const unsigned kWidth = 16, kHeight = 16;

int OpenDescriptors() {
  int count = 0;
  for (int fd = 0; fd < 1024; ++fd) count += fcntl(fd, F_GETFD) != -1;
  return count;
}

unsigned long Digest(const std::vector<unsigned char>& bytes) {
  unsigned long hash = 5381;
  for (size_t i = 0; i < bytes.size(); ++i) hash = hash * 33 + bytes[i];
  return hash;
}

void Golden(const char* name, unsigned error, const std::vector<unsigned char>& out, unsigned w = 0, unsigned h = 0) {
  printf("golden %s: error=%u size=%zu digest=%lu w=%u h=%u\n", name, error, out.size(), Digest(out), w, h);
}

}  // namespace

void* lodepng_malloc(size_t size) {
  void* p = malloc(size ? size : 1);
  if (p) ++g_live;
  return p;
}
void* lodepng_realloc(void* ptr, size_t size) {
  void* p = realloc(ptr, size ? size : 1);
  if (!ptr && p) ++g_live;
  return p;
}
void lodepng_free(void* ptr) {
  if (ptr) --g_live;
  free(ptr);
}

void* operator new(size_t size) {
  if (g_countdown == 0) {
    g_countdown = -1;
    throw std::bad_alloc();
  }
  if (g_countdown > 0) --g_countdown;
  void* p = malloc(size ? size : 1);
  if (!p) throw std::bad_alloc();
  return p;
}
void* operator new[](size_t size) { return operator new(size); }
void operator delete(void* p) noexcept { free(p); }
void operator delete[](void* p) noexcept { free(p); }
void operator delete(void* p, size_t) noexcept { free(p); }
void operator delete[](void* p, size_t) noexcept { free(p); }

namespace {

// Throws std::bad_alloc at the first, second, ... operator new inside the call
// until the call completes, and checks that nothing leaked after each throw.
template <class Call>
void SurvivesBadAlloc(const char* name, Call call) {
  for (long k = 0; k < 200; ++k) {
    long live = g_live;
    int fds = OpenDescriptors();
    bool threw = false;
    g_countdown = k;
    try {
      call();
    } catch (const std::bad_alloc&) {
      threw = true;
    }
    g_countdown = -1;
    if (g_live != live || OpenDescriptors() != fds) {
      printf("FAIL %s: bad_alloc at allocation %ld leaks %ld lodepng buffer(s) and %d file(s)\n", name, k + 1,
             g_live - live, OpenDescriptors() - fds);
      return;
    }
    if (!threw) {
      printf("PASS %s: no leak with bad_alloc at any of %ld allocation(s)\n", name, k);
      return;
    }
  }
  printf("FAIL %s: still throwing after 200 injected failures\n", name);
}

std::string Path(const char* name) { return g_dir + "/" + name; }

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  g_dir = argv[1];
  for (unsigned i = 0; i < kWidth * kHeight * 4; ++i) g_image.push_back(static_cast<unsigned char>((i * 7) ^ (i >> 3)));
  if (lodepng::encode(g_png, g_image, kWidth, kHeight) != 0) return 3;
  lodepng::State plain_state;
  if (lodepng::compress(g_zlib, g_image, plain_state.encoder.zlibsettings) != 0) return 3;
  const LodePNGCompressSettings& zc = plain_state.encoder.zlibsettings;
  const LodePNGDecompressSettings& zd = plain_state.decoder.zlibsettings;

  {
    std::vector<unsigned char> out(3, 9);
    unsigned w = 1, h = 1;
    unsigned error = lodepng::decode(out, w, h, g_png);
    Golden("decode-rgba-appends", error, out, w, h);
    out.clear();
    error = lodepng::decode(out, w, h, g_png.empty() ? 0 : &g_png[0], g_png.size(), LCT_RGB, 8);
    Golden("decode-rgb-pointer", error, out, w, h);
    lodepng::State state;
    out.assign(2, 1);
    error = lodepng::decode(out, w, h, state, g_png);
    Golden("decode-state-appends", error, out, w, h);
    printf("golden decode-state-info: colortype=%d bitdepth=%u\n", state.info_png.color.colortype,
           state.info_png.color.bitdepth);
    std::vector<unsigned char> junk(40, 0x55);
    out.assign(3, 7);
    w = h = 5;
    error = lodepng::decode(out, w, h, junk);
    Golden("decode-invalid", error, out, w, h);
    std::vector<unsigned char> empty;
    out.assign(3, 7);
    w = h = 5;
    error = lodepng::decode(out, w, h, state, empty);
    Golden("decode-state-empty", error, out, w, h);
  }
  {
    std::vector<unsigned char> out(4, 2);
    unsigned error = lodepng::encode(out, g_image, kWidth, kHeight);
    Golden("encode-appends", error, out);
    out.assign(4, 2);
    std::vector<unsigned char> small(10, 0);
    error = lodepng::encode(out, small, kWidth, kHeight);
    Golden("encode-input-too-small", error, out);
    lodepng::State state;
    state.info_raw.colortype = LCT_RGBA;
    state.info_png.color.colortype = LCT_RGB;
    state.encoder.auto_convert = 0;
    out.assign(1, 3);
    error = lodepng::encode(out, g_image.empty() ? 0 : &g_image[0], kWidth, kHeight, state);
    Golden("encode-state-pointer", error, out);
    out.assign(1, 3);
    error = lodepng::encode(out, small, kWidth, kHeight, state);
    Golden("encode-state-too-small", error, out);
  }
  {
    std::vector<unsigned char> out(2, 4);
    unsigned error = lodepng::compress(out, g_image, zc);
    Golden("compress-appends", error, out);
    out.assign(2, 4);
    error = lodepng::decompress(out, g_zlib, zd);
    Golden("decompress-appends", error, out);
    std::vector<unsigned char> junk(12, 0xff);
    out.assign(2, 4);
    error = lodepng::decompress(out, junk, zd);
    Golden("decompress-invalid", error, out);
  }
  {
    std::vector<unsigned char> out(2, 6);
    unsigned error = lodepng::save_file(g_png, Path("image.png"));
    Golden("save-file", error, out);
    error = lodepng::load_file(out, Path("image.png"));
    Golden("load-file-replaces", error, out);
    out.assign(2, 6);
    error = lodepng::load_file(out, Path("missing.png"));
    Golden("load-missing", error, out);
    lodepng::save_file(std::vector<unsigned char>(), Path("empty.bin"));
    out.assign(2, 6);
    error = lodepng::load_file(out, Path("empty.bin"));
    Golden("load-empty", error, out);
    unsigned w = 3, h = 3;
    out.assign(2, 6);
    error = lodepng::decode(out, w, h, Path("missing.png"));
    Golden("decode-missing-file", error, out, w, h);
    out.clear();
    error = lodepng::decode(out, w, h, Path("image.png"), LCT_GREY, 8);
    Golden("decode-file-grey", error, out, w, h);
    error = lodepng::encode(Path("no-such-dir/x.png"), g_image, kWidth, kHeight);
    Golden("encode-unwritable", error, std::vector<unsigned char>());
    error = lodepng::encode(Path("written.png"), g_image, kWidth, kHeight, LCT_RGBA, 8);
    out.clear();
    lodepng::load_file(out, Path("written.png"));
    Golden("encode-file", error, out);
  }

  SurvivesBadAlloc("decompress", [&] { std::vector<unsigned char> out; lodepng::decompress(out, g_zlib, zd); });
  SurvivesBadAlloc("compress", [&] { std::vector<unsigned char> out; lodepng::compress(out, g_image, zc); });
  SurvivesBadAlloc("decode to RGBA", [&] { std::vector<unsigned char> out; unsigned w, h; lodepng::decode(out, w, h, g_png); });
  SurvivesBadAlloc("decode with State", [&] {
    std::vector<unsigned char> out; unsigned w, h; lodepng::State state; lodepng::decode(out, w, h, state, g_png); });
  SurvivesBadAlloc("encode", [&] { std::vector<unsigned char> out; lodepng::encode(out, g_image, kWidth, kHeight); });
  SurvivesBadAlloc("encode with State", [&] {
    std::vector<unsigned char> out; lodepng::State state; lodepng::encode(out, g_image, kWidth, kHeight, state); });
  SurvivesBadAlloc("load_file", [&] { std::vector<unsigned char> out; lodepng::load_file(out, Path("image.png")); });
  SurvivesBadAlloc("decode from file", [&] {
    std::vector<unsigned char> out; unsigned w, h; lodepng::decode(out, w, h, Path("image.png")); });
  SurvivesBadAlloc("encode to file", [&] { lodepng::encode(Path("fault.png"), g_image, kWidth, kHeight); });
  return 0;
}
