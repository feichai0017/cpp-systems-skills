#include "config.hpp"

#include <cassert>

int main() {
    const project::ValueConfig config(128, project::QuantizationMode::Bfloat16);
    assert(config.Quantize() == project::QuantizationMode::Bfloat16);
    assert(config.Size() == 128);
}
