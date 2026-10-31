#include "decoder.hpp"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, std::size_t size) {
    (void)project::DecodeFrame(std::as_bytes(std::span(data, size)));
    return 0;
}
