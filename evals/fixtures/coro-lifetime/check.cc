#include "service.hpp"

#include <cassert>
#include <string>
#include <vector>

namespace {

std::string Tenant() { return "tenant-with-a-fairly-long-name"; }

std::vector<project::Item> LoadItems() {
    return {{"first-key-that-is-long-enough", "first-value-that-is-long-enough"},
            {"second-key-that-is-long-enough", "second-value-that-is-long-enough"}};
}

}  // namespace

int main() {
    project::ManualExecutor executor;
    project::Store store(executor);
    // The batch is prepared first and run later, as the request handler does.
    project::Task<std::error_code> batch = project::WriteBatch(store, Tenant(), LoadItems());
    assert(!project::SyncWait(executor, std::move(batch)));
    assert(store.Get(Tenant() + "/first-key-that-is-long-enough") == "first-value-that-is-long-enough");
    assert(store.Get(Tenant() + "/second-key-that-is-long-enough") == "second-value-that-is-long-enough");
}
