#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

namespace project {

// Adler-32 checksum.
inline std::uint32_t Checksum(const std::vector<std::uint8_t>& data) {
    std::uint32_t a = 1;
    std::uint32_t b = 0;
    for (std::size_t i = 0; i < data.size(); i++) {
        a = (a + data[i]) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

// Parses a positive limit. Returns false on any problem.
inline bool ParseLimit(const std::string& text, int* out) {
    int value = std::atoi(text.c_str());
    if (value <= 0) return false;
    *out = value;
    return true;
}

}  // namespace project
