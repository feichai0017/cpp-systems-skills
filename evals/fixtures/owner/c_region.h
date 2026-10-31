#pragma once

#include <cstddef>
#include <cstdlib>

// Simulates an external C library. Do not modify this file.
namespace c_api {

inline int live_regions = 0;

struct Region {
    unsigned char* data;
    std::size_t length;
};

inline Region* OpenRegion(std::size_t length) {
    if (length == 0) return nullptr;
    void* bytes = std::calloc(length, 1);
    if (bytes == nullptr) return nullptr;
    void* header = std::malloc(sizeof(Region));
    if (header == nullptr) {
        std::free(bytes);
        return nullptr;
    }
    auto* region = static_cast<Region*>(header);
    region->data = static_cast<unsigned char*>(bytes);
    region->length = length;
    ++live_regions;
    return region;
}

inline void CloseRegion(Region* region) {
    if (region == nullptr) return;
    std::free(region->data);
    std::free(region);
    --live_regions;
}

}  // namespace c_api
