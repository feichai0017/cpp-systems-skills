#pragma once

#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>

#include "async.hpp"

namespace project {

class Store {
public:
    explicit Store(ManualExecutor& executor) : executor_(executor) {}

    // Stores `value` under `key`. The write runs on the executor.
    Task<std::error_code> Put(const std::string& key, std::string_view value) {
        co_await executor_.Schedule();
        if (key.empty()) co_return std::make_error_code(std::errc::invalid_argument);
        data_[key] = std::string(value);
        co_return std::error_code{};
    }

    std::optional<std::string> Get(const std::string& key) const {
        const auto it = data_.find(key);
        if (it == data_.end()) return std::nullopt;
        return it->second;
    }

private:
    ManualExecutor& executor_;
    std::map<std::string, std::string> data_;
};

}  // namespace project
