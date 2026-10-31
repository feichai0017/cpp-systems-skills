#include "config.hpp"

#include <cassert>

int main() {
    const project::Frame frame{{1, 2, 3, 4}, {9, 20, 30, 40, 50}, "orbit"};
    assert(project::HeaderChecksum(frame) == 0x18000bu);
    assert(project::PayloadChecksum(frame) == 0xa3005bu);
    assert(project::NameChecksum(frame) == 0x6640221u);

    int limit = 0;
    assert(project::ParseLimit("42", &limit) && limit == 42);
    assert(!project::ParseLimit("abc", &limit));
}
