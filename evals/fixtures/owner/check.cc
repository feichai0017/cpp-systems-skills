#include "loader.hpp"

#include <cassert>

int main() {
    const unsigned char good[] = {0x7f, 3};
    const unsigned char bad[] = {0x00, 1};

    project::Header header;
    assert(project::LoadHeader(good, sizeof(good), &header));
    assert(header.version == 3);
    assert(!project::LoadHeader(bad, sizeof(bad), &header));
    assert(c_api::live_regions == 0);
}
