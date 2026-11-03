#include "decoder.hpp"

#include <cassert>
#include <vector>

int main() {
    const std::vector<std::byte> frame{
        std::byte{0x4B}, std::byte{0x56}, std::byte{1}, std::byte{7},
        std::byte{3}, std::byte{0}, std::byte{0}, std::byte{0},
        std::byte{'a'}, std::byte{'b'}, std::byte{'c'}};
    const auto decoded = project::DecodeFrame(frame);
    assert(decoded.ok());
    assert(decoded.value().version == 1 && decoded.value().type == 7);
    assert(decoded.value().payload.size() == 3);

    const std::vector<std::byte> truncated(frame.begin(), frame.begin() + 4);
    const auto short_result = project::DecodeFrame(truncated);
    assert(!short_result.ok() && short_result.error() == project::DecodeError::kTruncated);
}
