#include "checksum/crc32.h"

#include <array>

namespace kvstore::checksum {
namespace {

constexpr std::array<std::uint32_t, 256> MakeTable() {
    std::array<std::uint32_t, 256> table{};
    for (std::uint32_t i = 0; i < 256; ++i) {
        std::uint32_t value = i;
        for (int bit = 0; bit < 8; ++bit) {
            value = (value & 1u) != 0 ? (value >> 1) ^ 0xEDB88320u : value >> 1;
        }
        table[i] = value;
    }
    return table;
}

constexpr auto kTable = MakeTable();

}  // namespace

std::uint32_t Crc32(std::span<const std::byte> data) {
    std::uint32_t crc = 0xFFFFFFFFu;
    for (const std::byte byte : data) {
        crc = kTable[(crc ^ std::to_integer<std::uint32_t>(byte)) & 0xFFu] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

}  // namespace kvstore::checksum
