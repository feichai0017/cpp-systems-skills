#include "kvstore/storage/segment.h"

namespace kvstore::storage {

std::size_t EncodedRecordBytes(std::size_t payload_bytes) {
    return kRecordHeaderBytes + payload_bytes;
}

}  // namespace kvstore::storage
