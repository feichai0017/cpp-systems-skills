#pragma once

#include <cstdint>
#include <cstring>
#include <span>

#include "protocol.hpp"
#include "result.hpp"

namespace project {

struct WireHeader {
    std::uint16_t magic;
    std::uint8_t version;
    std::uint8_t type;
    std::uint32_t payload_bytes;
};

// Decodes the single frame contained in `input`.
inline Result<Frame, DecodeError> DecodeFrame(std::span<const std::byte> input) {
    const auto* header = reinterpret_cast<const WireHeader*>(input.data());
    if (header->magic != kMagic) return DecodeError::kBadMagic;
    Frame frame;
    frame.version = header->version;
    frame.type = header->type;
    frame.payload.resize(header->payload_bytes);
    std::memcpy(frame.payload.data(), input.data() + sizeof(WireHeader), header->payload_bytes);
    return frame;
}

}  // namespace project
