#pragma once

#include <cstddef>
#include <cstdint>

namespace kvstore::storage {

inline constexpr std::size_t kRecordHeaderBytes = 8;

// Bytes needed to store a record with the given payload size.
[[nodiscard]] std::size_t EncodedRecordBytes(std::size_t payload_bytes);

}  // namespace kvstore::storage
