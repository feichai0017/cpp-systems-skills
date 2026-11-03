#pragma once

#include <utility>
#include <variant>

namespace project {

template <typename T, typename E>
class [[nodiscard]] Result {
public:
    Result(T value) : state_(std::move(value)) {}
    Result(E error) : state_(error) {}

    bool ok() const { return std::holds_alternative<T>(state_); }
    const T& value() const { return std::get<T>(state_); }
    E error() const { return std::get<E>(state_); }

private:
    std::variant<T, E> state_;
};

}  // namespace project
