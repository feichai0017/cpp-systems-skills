#pragma once

#include <utility>
#include <variant>

namespace kvstore {

enum class ErrorCode { kInvalidArgument, kTruncated, kCorrupted };

template <typename T>
class [[nodiscard]] Result {
public:
    Result(T value) : state_(std::move(value)) {}
    Result(ErrorCode error) : state_(error) {}

    bool ok() const { return std::holds_alternative<T>(state_); }
    const T& value() const& { return std::get<T>(state_); }
    T&& value() && { return std::get<T>(std::move(state_)); }
    ErrorCode error() const { return std::get<ErrorCode>(state_); }

private:
    std::variant<T, ErrorCode> state_;
};

}  // namespace kvstore
