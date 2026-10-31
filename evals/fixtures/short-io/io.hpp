#pragma once

#include <cerrno>
#include <cstddef>
#include <functional>
#include <span>
#include <system_error>

namespace project {

// Returns bytes written, or -1 with errno set.
using WriteFn = std::function<long(const std::byte* data, std::size_t size)>;

inline std::error_code SendRecord(const WriteFn& write, std::span<const std::byte> record) {
    const long written = write(record.data(), record.size());
    if (written < 0) return {errno, std::system_category()};
    return {};
}

}  // namespace project
