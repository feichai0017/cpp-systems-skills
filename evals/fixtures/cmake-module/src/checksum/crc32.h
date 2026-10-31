#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

namespace kvstore::checksum {

// CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320).
[[nodiscard]] std::uint32_t Crc32(std::span<const std::byte> data);

}  // namespace kvstore::checksum
