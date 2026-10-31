#pragma once

#include <cstddef>
#include <cstring>

#include "c_region.h"

namespace project {

struct Header {
    unsigned char magic = 0;
    unsigned char version = 0;
};

// Copies the input into a scratch region and decodes the header.
// Returns false when the header is invalid.
inline bool LoadHeader(const unsigned char* input, std::size_t length, Header* out) {
    c_api::Region* region = c_api::OpenRegion(length);
    if (region == nullptr) return false;
    std::memcpy(region->data, input, length);
    if (length < 2 || region->data[0] != 0x7f) {
        return false;
    }
    out->magic = region->data[0];
    out->version = region->data[1];
    c_api::CloseRegion(region);
    return true;
}

}  // namespace project
