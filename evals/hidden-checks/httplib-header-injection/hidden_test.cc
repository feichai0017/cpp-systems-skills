// Reviewer-only probe for the httplib-header-injection fixture.
// A raw TCP listener records the bytes each client entry point sends, so the check
// sees the request on the wire rather than the Request object.
#include "httplib.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdio>
#include <functional>
#include <string>
#include <thread>

namespace {

struct Wire {
  std::string request;
  int status = -1;
};

std::string ReadRequest(int fd) {
  std::string data;
  char buf[4096];
  size_t header_end = std::string::npos;
  size_t body = 0;
  while (true) {
    ssize_t n = recv(fd, buf, sizeof buf, 0);
    if (n <= 0) break;
    data.append(buf, static_cast<size_t>(n));
    if (header_end == std::string::npos) {
      header_end = data.find("\r\n\r\n");
      if (header_end == std::string::npos) continue;
      auto pos = data.find("Content-Length: ");
      if (pos != std::string::npos && pos < header_end) body = std::stoul(data.substr(pos + 16));
    }
    if (data.size() >= header_end + 4 + body) break;
  }
  return data;
}

// Runs one client call against a listener that answers 200 and records the request.
Wire Capture(const std::function<httplib::Result(httplib::Client&)>& call) {
  int listener = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  bind(listener, reinterpret_cast<sockaddr*>(&addr), sizeof addr);
  socklen_t len = sizeof addr;
  getsockname(listener, reinterpret_cast<sockaddr*>(&addr), &len);
  listen(listener, 1);
  Wire wire;
  std::thread server([&] {
    int fd = accept(listener, nullptr, nullptr);
    if (fd < 0) return;
    timeval timeout{3, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    wire.request = ReadRequest(fd);
    const char reply[] = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    send(fd, reply, sizeof reply - 1, 0);
    close(fd);
  });
  {
    httplib::Client cli("127.0.0.1", ntohs(addr.sin_port));
    cli.set_connection_timeout(2);
    cli.set_read_timeout(3);
    auto res = call(cli);
    if (res) wire.status = res->status;
  }
  shutdown(listener, SHUT_RDWR);
  server.join();
  close(listener);
  return wire;
}

bool Injected(const std::string& request) {
  return request.find("\r\nX-Injected") != std::string::npos || request.find("\nX-Injected") != std::string::npos;
}

int failures = 0;

void Entry(const char* name, const std::function<httplib::Result(httplib::Client&)>& call) {
  Wire wire = Capture(call);
  if (wire.request.empty() || wire.status != 200) {
    std::printf("FAIL entry %s: request not sent (status %d)\n", name, wire.status);
    ++failures;
  } else if (Injected(wire.request)) {
    std::printf("FAIL entry %s: injected header on the wire\n", name);
    ++failures;
  } else {
    std::printf("PASS entry %s\n", name);
  }
}

void Control(const char* name, const std::function<httplib::Result(httplib::Client&)>& call, const char* expected) {
  Wire wire = Capture(call);
  if (wire.status == 200 && wire.request.find(expected) != std::string::npos) {
    std::printf("PASS control %s\n", name);
  } else {
    std::printf("FAIL control %s: \"%s\" missing from the request\n", name, expected);
    ++failures;
  }
}

const std::string kType = "text/plain\r\nX-Injected: 1";
const std::string kValue = "a\r\nX-Injected: 1";

}  // namespace

int main() {
  using httplib::Client;
  using httplib::Headers;
  Entry("Post content_type", [](Client& c) { return c.Post("/p", "body", kType); });
  Entry("Put content_type", [](Client& c) { return c.Put("/p", "body", kType); });
  Entry("Patch content_type", [](Client& c) { return c.Patch("/p", "body", kType); });
  Entry("Delete content_type", [](Client& c) { return c.Delete("/p", "body", kType); });
  Entry("Post content provider", [](Client& c) {
    return c.Post("/p", 4, [](size_t offset, size_t length, httplib::DataSink& sink) {
      sink.write("body" + offset, length);
      return true;
    }, kType);
  });
  Entry("Get Headers value", [](Client& c) { return c.Get("/g", Headers{{"X-Test", kValue}}); });
  Entry("Get Headers name", [](Client& c) { return c.Get("/g", Headers{{"X-Test\r\nX-Injected", "1"}}); });
  Entry("Get Headers LF only", [](Client& c) { return c.Get("/g", Headers{{"X-Test", "a\nX-Injected: 1"}}); });
  Entry("Post Headers", [](Client& c) { return c.Post("/p", Headers{{"X-Test", kValue}}, "body", "text/plain"); });
  Entry("set_default_headers", [](Client& c) {
    c.set_default_headers(Headers{{"X-Default", kValue}});
    return c.Get("/g");
  });
  Entry("set_bearer_token_auth", [](Client& c) {
    c.set_bearer_token_auth("token\r\nX-Injected: 1");
    return c.Get("/g");
  });
  Control("Content-Type kept", [](Client& c) { return c.Post("/p", "{}", "application/json"); },
          "Content-Type: application/json\r\n");
  Control("value with colon and tab kept", [](Client& c) { return c.Get("/g", Headers{{"X-Ok", "a:b\tc"}}); },
          "X-Ok: a:b\tc\r\n");
  Control("UTF-8 value kept", [](Client& c) { return c.Get("/g", Headers{{"X-Utf8", "caf\xc3\xa9"}}); },
          "X-Utf8: caf\xc3\xa9\r\n");
  return failures == 0 ? 0 : 1;
}
