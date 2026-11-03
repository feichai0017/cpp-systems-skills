#pragma once

#include <string>
#include <system_error>
#include <vector>

#include "async.hpp"
#include "store.hpp"

namespace project {

struct Item {
    std::string key;
    std::string value;
};

// Writes every item under the tenant's namespace and returns the first error.
inline Task<std::error_code> WriteBatch(Store& store, const std::string& tenant, const std::vector<Item>& items) {
    std::vector<Task<std::error_code>> writes;
    writes.reserve(items.size());
    for (const Item& item : items) {
        writes.push_back(store.Put(tenant + "/" + item.key, item.value));
    }
    co_return co_await AwaitAll(std::move(writes));
}

}  // namespace project
