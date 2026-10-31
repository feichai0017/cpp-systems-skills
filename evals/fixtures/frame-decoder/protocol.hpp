#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace project {

// Frame layout on the wire (little-endian):
//   uint16 magic | uint8 version | uint8 type | uint32 payload_bytes | payload
inline constexpr std::uint16_t kMagic = 0x564B;
inline constexpr std::size_t kHeaderBytes = 8;
inline constexpr std::size_t kMaxPayloadBytes = std::size_t{1} << 20;

enum class DecodeError { kTruncated, kBadMagic, kTooLarge, kTrailingBytes };

struct Frame {
    std::uint8_t version = 0;
    std::uint8_t type = 0;
    std::vector<std::byte> payload;
};

}  // namespace project
