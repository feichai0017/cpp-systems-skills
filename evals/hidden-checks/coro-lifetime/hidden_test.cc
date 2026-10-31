// Reviewer-only check: the store API must stay safe when tasks are created first and awaited later.
#include "service.hpp"

#include <cstdio>
#include <string>
#include <vector>

namespace {

int failures = 0;
void Expect(bool ok, const char* what) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++failures;
}

project::Task<std::error_code> PutAndAwait(project::Store& store) {
    co_return co_await store.Put(std::string(40, 'a'), std::string(40, 'b'));
}

}  // namespace

int main() {
    project::ManualExecutor executor;
    project::Store store(executor);

    project::Task<std::error_code> deferred = store.Put(std::string(48, 'k'), std::string(48, 'v'));
    Expect(!project::SyncWait(executor, std::move(deferred)) && store.Get(std::string(48, 'k')) == std::string(48, 'v'),
           "Put with temporary arguments awaited later");

    Expect(!project::SyncWait(executor, PutAndAwait(store)) && store.Get(std::string(40, 'a')) == std::string(40, 'b'),
           "Put awaited immediately still works");

    project::Task<std::error_code> empty = store.Put(std::string(), std::string(48, 'x'));
    Expect(project::SyncWait(executor, std::move(empty)) == std::errc::invalid_argument, "empty key still rejected");

    std::printf(failures == 0 ? "hidden lifetime: PASS\n" : "hidden lifetime: %d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
