// Reviewer-only check: adversarial frames under ASan/UBSan.
#include "decoder.hpp"

#include <cstdio>
#include <vector>

namespace {

int failures = 0;
void Expect(bool ok, const char* what) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++failures;
}

std::vector<std::byte> Frame(std::uint32_t length, std::size_t actual_payload, std::uint16_t magic = project::kMagic) {
    std::vector<std::byte> out{std::byte(magic & 0xFF), std::byte(magic >> 8), std::byte{2}, std::byte{9},
                               std::byte(length & 0xFF), std::byte((length >> 8) & 0xFF),
                               std::byte((length >> 16) & 0xFF), std::byte(length >> 24)};
    for (std::size_t i = 0; i < actual_payload; ++i) out.push_back(std::byte(i & 0xFF));
    return out;
}

bool Is(const project::Result<project::Frame, project::DecodeError>& r, project::DecodeError e) {
    return !r.ok() && r.error() == e;
}

}  // namespace

int main() {
    using project::DecodeError;
    using project::DecodeFrame;
    {
        const auto r = DecodeFrame(Frame(5, 5));
        Expect(r.ok() && r.value().payload.size() == 5 && r.value().version == 2, "valid frame");
    }
    {
        auto bytes = Frame(5, 5);
        bytes.insert(bytes.begin(), std::byte{0});
        const auto r = DecodeFrame(std::span<const std::byte>(bytes).subspan(1));
        Expect(r.ok() && r.value().payload.size() == 5, "valid frame at an unaligned address");
    }
    Expect(Is(DecodeFrame({}), DecodeError::kTruncated), "empty input");
    {
        const auto bytes = Frame(5, 5);
        Expect(Is(DecodeFrame(std::span(bytes).first(7)), DecodeError::kTruncated), "header cut short");
    }
    Expect(Is(DecodeFrame(Frame(100, 10)), DecodeError::kTruncated), "payload shorter than declared");
    Expect(Is(DecodeFrame(Frame(0xFFFFFFFFu, 4)), DecodeError::kTooLarge), "huge declared length is rejected without allocating");
    Expect(Is(DecodeFrame(Frame(static_cast<std::uint32_t>(project::kMaxPayloadBytes + 1), 0)), DecodeError::kTooLarge), "just over the limit");
    Expect(Is(DecodeFrame(Frame(5, 5, 0x1234)), DecodeError::kBadMagic), "bad magic");
    Expect(Is(DecodeFrame(Frame(5, 7)), DecodeError::kTrailingBytes), "trailing bytes");
    {
        const auto r = DecodeFrame(Frame(0, 0));
        Expect(r.ok() && r.value().payload.empty(), "empty payload");
    }
    std::printf(failures == 0 ? "hidden decoder: PASS\n" : "hidden decoder: %d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
