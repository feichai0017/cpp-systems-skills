#pragma once

#include <cstddef>

namespace project {

enum class QuantizationMode { None, Bfloat16 };

class ValueConfig {
public:
    ValueConfig(std::size_t stored_value_bytes, QuantizationMode mode)
        : stored_value_bytes_(stored_value_bytes), mode_(mode) {}

    QuantizationMode Quantize() const { return mode_; }
    std::size_t Size() const { return stored_value_bytes_; }

private:
    std::size_t stored_value_bytes_;
    QuantizationMode mode_;
};

}  // namespace project
