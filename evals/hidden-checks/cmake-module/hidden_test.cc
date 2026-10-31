// Reviewer-only behavior check. RECORDS_HEADER is the header that declares ReadRecords.
#include RECORDS_HEADER

#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "checksum/crc32.h"

namespace {

void AppendLe32(std::vector<std::byte>& out, std::uint32_t value) {
    for (int shift = 0; shift < 32; shift += 8) out.push_back(std::byte((value >> shift) & 0xFFu));
}

void AppendRecord(std::vector<std::byte>& out, std::span<const std::byte> payload) {
    AppendLe32(out, static_cast<std::uint32_t>(payload.size()));
    AppendLe32(out, kvstore::checksum::Crc32(payload));
    out.insert(out.end(), payload.begin(), payload.end());
}

int failures = 0;
void Expect(bool condition, const char* what) {
    if (!condition) {
        std::printf("FAIL: %s\n", what);
        ++failures;
    }
}

}  // namespace

int main() {
    using kvstore::ErrorCode;
    using kvstore::storage::ReadRecords;
    const std::array<std::byte, 3> a{std::byte{1}, std::byte{2}, std::byte{3}};
    const std::array<std::byte, 0> empty{};

    std::vector<std::byte> segment;
    AppendRecord(segment, a);
    AppendRecord(segment, empty);
    {
        const auto result = ReadRecords(segment);
        Expect(result.ok(), "two valid records decode");
        if (result.ok()) {
            Expect(result.value().size() == 2, "two records returned");
            const auto& payload = result.value()[0].payload;
            Expect(payload.size() == 3, "first payload size");
            Expect(payload.data() == segment.data() + 8, "payload borrows the input without copying");
            Expect(result.value()[1].payload.empty(), "zero-length payload accepted");
        }
    }
    {
        const auto result = ReadRecords(std::span<const std::byte>());
        Expect(result.ok() && result.value().empty(), "empty input yields no records");
    }
    {
        const auto result = ReadRecords(std::span(segment).first(5));
        Expect(!result.ok() && result.error() == ErrorCode::kTruncated, "short header is truncated");
    }
    {
        const auto result = ReadRecords(std::span(segment).first(10));
        Expect(!result.ok() && result.error() == ErrorCode::kTruncated, "payload beyond input is truncated");
    }
    {
        std::vector<std::byte> huge;
        AppendLe32(huge, 0xFFFFFFFFu);
        AppendLe32(huge, 0);
        huge.push_back(std::byte{0});
        const auto result = ReadRecords(huge);
        Expect(!result.ok() && result.error() == ErrorCode::kTruncated, "huge length does not overflow");
    }
    {
        std::vector<std::byte> corrupt = segment;
        corrupt[9] ^= std::byte{0x40};
        const auto result = ReadRecords(corrupt);
        Expect(!result.ok() && result.error() == ErrorCode::kCorrupted, "checksum mismatch is corrupted");
    }
    {
        std::vector<std::byte> shifted(1);
        shifted.insert(shifted.end(), segment.begin(), segment.end());
        const auto result = ReadRecords(std::span(shifted).subspan(1));   // unaligned start
        Expect(result.ok() && result.value().size() == 2, "unaligned input decodes");
    }
    std::printf(failures == 0 ? "hidden behavior: PASS\n" : "hidden behavior: %d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
