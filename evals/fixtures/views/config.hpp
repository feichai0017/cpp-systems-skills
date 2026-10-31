#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "checksum.hpp"

namespace project {

struct Frame {
    std::array<std::uint8_t, 4> header;
    std::vector<std::uint8_t> payload;  // checksum covers payload[1, 4)
    std::string name;
};

inline std::uint32_t HeaderChecksum(const Frame& frame) {
    std::vector<std::uint8_t> copy(frame.header.begin(), frame.header.end());
    return Checksum(copy);
}

inline std::uint32_t PayloadChecksum(const Frame& frame) {
    std::vector<std::uint8_t> copy(frame.payload.begin() + 1, frame.payload.begin() + 4);
    return Checksum(copy);
}

inline std::uint32_t NameChecksum(const Frame& frame) {
    std::vector<std::uint8_t> copy(frame.name.begin(), frame.name.end());
    return Checksum(copy);
}

}  // namespace project
