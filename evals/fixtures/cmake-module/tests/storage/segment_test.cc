#include "kvstore/storage/segment.h"

#include <cassert>

int main() {
    assert(kvstore::storage::EncodedRecordBytes(0) == 8);
    assert(kvstore::storage::EncodedRecordBytes(5) == 13);
}
