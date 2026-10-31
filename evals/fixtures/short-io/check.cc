#include "io.hpp"

#include <array>
#include <cassert>
#include <vector>

int main() {
    const std::array<std::byte, 10> record{
        std::byte{0}, std::byte{1}, std::byte{2}, std::byte{3}, std::byte{4},
        std::byte{5}, std::byte{6}, std::byte{7}, std::byte{8}, std::byte{9}};

    // The simulated OS accepts at most 3 bytes per call and is interrupted once.
    std::vector<std::byte> sink;
    bool interrupted = false;
    const project::WriteFn partial = [&](const std::byte* data, std::size_t size) -> long {
        if (!interrupted) {
            interrupted = true;
            errno = EINTR;
            return -1;
        }
        const std::size_t n = size < 3 ? size : 3;
        sink.insert(sink.end(), data, data + n);
        return static_cast<long>(n);
    };
    assert(!project::SendRecord(partial, record));
    assert(sink.size() == record.size());

    const project::WriteFn broken = [](const std::byte*, std::size_t) -> long {
        errno = EIO;
        return -1;
    };
    assert(project::SendRecord(broken, record) == std::errc::io_error);
}
