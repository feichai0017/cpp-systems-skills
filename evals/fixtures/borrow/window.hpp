#pragma once

#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace project {

class ReadWindow {
public:
    explicit ReadWindow(std::shared_ptr<const std::string> storage)
        : storage_(std::move(storage)) {}
    std::string_view View() const { return *storage_; }

private:
    std::shared_ptr<const std::string> storage_;
};

class Store {
public:
    void Replace(std::string text) {
        current_ = std::make_shared<const std::string>(std::move(text));
    }
    std::optional<ReadWindow> Read() const {
        if (!current_) return std::nullopt;
        return ReadWindow(current_);
    }

private:
    std::shared_ptr<const std::string> current_;
};

}  // namespace project
