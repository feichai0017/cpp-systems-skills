// Behavior probe for TiXmlDocument::LoadFile. Lines starting with "golden" must
// match the output of the imported original; lines starting with "rule" state
// whether a fault-injection expectation holds.
#include "tinyxml.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>

namespace {

std::string g_dir;

std::string Escape(const char* text) {
  if (!text) return "(null)";
  std::string out;
  for (const unsigned char* p = reinterpret_cast<const unsigned char*>(text); *p; ++p) {
    char buf[8];
    if (*p == '\n') out += "\\n";
    else if (*p == '\r') out += "\\r";
    else if (*p < 0x20 || *p >= 0x7f) { snprintf(buf, sizeof buf, "\\x%02x", *p); out += buf; }
    else out += static_cast<char>(*p);
  }
  return out;
}

std::string Describe(TiXmlDocument& doc, bool ok) {
  std::string out = ok ? "ok" : "fail";
  char buf[64];
  snprintf(buf, sizeof buf, " error=%d", doc.ErrorId());
  out += buf;
  for (TiXmlNode* node = doc.FirstChild(); node; node = node->NextSibling()) {
    out += " [";
    snprintf(buf, sizeof buf, "%d:", node->Type());
    out += buf;
    out += Escape(node->Value());
    if (TiXmlElement* element = node->ToElement()) {
      out += "=";
      out += Escape(element->GetText());
    }
    out += "]";
  }
  return out;
}

std::string WriteFile(const char* name, const char* data, size_t size) {
  std::string path = g_dir + "/" + name;
  FILE* file = fopen(path.c_str(), "wb");
  if (!file || fwrite(data, 1, size, file) != size || fclose(file) != 0) {
    perror(path.c_str());
    exit(2);
  }
  return path;
}

void Golden(const char* name, const char* data, size_t size, long skip_before_load) {
  std::string path = WriteFile(name, data, size);
  FILE* file = fopen(path.c_str(), "rb");
  if (skip_before_load > 0) fseek(file, skip_before_load, SEEK_SET);
  TiXmlDocument doc;
  bool ok = doc.LoadFile(file);
  long position = ftell(file);
  fclose(file);
  printf("golden %s: %s position=%s\n", name, Describe(doc, ok).c_str(),
         position == static_cast<long>(size) ? "end" : "other");
}

// A FILE* whose seek or read operations fail on demand.
struct FaultyStream {
  const char* data;
  long size;
  long pos;
  bool fail_seek_end;
  bool fail_seek_cur;
  bool fail_seek_set;
  long read_limit;  // bytes readable before EOF; -1 means size; -2 means read error
};

int FaultyRead(void* cookie, char* out, int count) {
  FaultyStream* s = static_cast<FaultyStream*>(cookie);
  if (s->read_limit == -2) { errno = EIO; return -1; }
  long limit = s->read_limit < 0 ? s->size : s->read_limit;
  long available = limit - s->pos;
  if (available <= 0) return 0;
  long n = count < available ? count : available;
  memcpy(out, s->data + s->pos, static_cast<size_t>(n));
  s->pos += n;
  return static_cast<int>(n);
}

long FaultySeek(FaultyStream* s, long offset, int whence) {
  if ((whence == SEEK_END && s->fail_seek_end) || (whence == SEEK_CUR && s->fail_seek_cur) ||
      (whence == SEEK_SET && s->fail_seek_set)) {
    errno = ESPIPE;
    return -1;
  }
  long base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? s->pos : s->size;
  s->pos = base + offset;
  return s->pos;
}

#if defined(__APPLE__) || defined(__FreeBSD__)
fpos_t SeekThunk(void* cookie, fpos_t offset, int whence) {
  return FaultySeek(static_cast<FaultyStream*>(cookie), static_cast<long>(offset), whence);
}
int CloseThunk(void*) { return 0; }
FILE* OpenFaulty(FaultyStream* s) {
  FILE* file = funopen(s, FaultyRead, 0, SeekThunk, CloseThunk);
  setvbuf(file, 0, _IONBF, 0);
  return file;
}
#else
ssize_t ReadThunk(void* cookie, char* out, size_t count) {
  return FaultyRead(cookie, out, static_cast<int>(count));
}
int SeekThunk(void* cookie, off64_t* offset, int whence) {
  long result = FaultySeek(static_cast<FaultyStream*>(cookie), static_cast<long>(*offset), whence);
  if (result < 0) return -1;
  *offset = result;
  return 0;
}
int CloseThunk(void*) { return 0; }
FILE* OpenFaulty(FaultyStream* s) {
  cookie_io_functions_t io = {ReadThunk, 0, SeekThunk, CloseThunk};
  FILE* file = fopencookie(s, "r", io);
  setvbuf(file, 0, _IONBF, 0);
  return file;
}
#endif

const char kTwoElements[] = "<a>1</a><b>2</b>";

// The load either fails with an error or yields the complete document.
void Rule(const char* name, FaultyStream stream) {
  stream.data = kTwoElements;
  stream.size = static_cast<long>(sizeof kTwoElements - 1);
  FILE* file = OpenFaulty(&stream);
  TiXmlDocument doc;
  bool ok = doc.LoadFile(file);
  fclose(file);
  bool complete = ok && doc.FirstChildElement("a") && doc.FirstChildElement("b");
  bool honest = (!ok && doc.Error()) || complete;
  printf("rule %s: %s (%s)\n", name, honest ? "ok" : "BAD", Describe(doc, ok).c_str());
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  g_dir = argv[1];
  TiXmlBase::SetCondenseWhiteSpace(false);

  const char newlines[] = "<a>x\r\ny\rz\r\r\nw\n</a>\r<b>\r</b>\r\n";
  Golden("newlines", newlines, sizeof newlines - 1, 0);
  Golden("newlines-after-seek", newlines, sizeof newlines - 1, 5);
  const char crlf_only[] = "\r\n\r\n<a>q</a>";
  Golden("leading-crlf", crlf_only, sizeof crlf_only - 1, 0);
  const char trailing_cr[] = "<a>t</a>\r";
  Golden("trailing-cr", trailing_cr, sizeof trailing_cr - 1, 0);
  const char nul[] = "<a>x</a>\0<b>y</b>";
  Golden("embedded-nul", nul, sizeof nul - 1, 0);
  const char bom[] = "\xef\xbb\xbf<a>\xc3\xa9</a>";
  Golden("utf8-bom", bom, sizeof bom - 1, 0);
  const char broken[] = "<a><b></a>";
  Golden("parse-error", broken, sizeof broken - 1, 0);
  Golden("empty", "", 0, 0);

  std::string big = "<r>";
  for (int i = 0; i < 20000; ++i) big += "<i>line\r\n</i>";
  big += "</r>";
  Golden("large", big.data(), big.size(), 0);

  {
    TiXmlDocument doc;
    bool ok = doc.LoadFile(static_cast<FILE*>(0));
    printf("golden null-file: %s\n", Describe(doc, ok).c_str());
  }
  {
    std::string first = WriteFile("first", "<old/>", 6);
    std::string empty = WriteFile("second-empty", "", 0);
    TiXmlDocument doc;
    bool loaded = doc.LoadFile(first.c_str());
    bool ok = doc.LoadFile(empty.c_str());
    printf("golden reload-empty: first=%d %s\n", loaded, Describe(doc, ok).c_str());
  }
  {
    std::string missing = g_dir + "/does-not-exist.xml";
    TiXmlDocument doc;
    bool ok = doc.LoadFile(missing.c_str());
    printf("golden missing-path: %s value=%s\n", Describe(doc, ok).c_str(),
           strcmp(doc.Value(), missing.c_str()) == 0 ? "path" : Escape(doc.Value()).c_str());
  }

  FaultyStream seek_end = {0, 0, 8, true, false, false, -1};
  Rule("seek-end-fails", seek_end);
  FaultyStream seek_cur = {0, 0, 0, false, true, false, -1};
  Rule("tell-fails", seek_cur);
  FaultyStream seek_set = {0, 0, 0, false, false, true, -1};
  Rule("seek-set-fails", seek_set);
  FaultyStream short_read = {0, 0, 0, false, false, false, 8};
  Rule("short-read", short_read);
  FaultyStream read_error = {0, 0, 0, false, false, false, -2};
  Rule("read-error", read_error);
  return 0;
}
