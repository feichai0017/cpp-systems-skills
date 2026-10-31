#pragma once

#include <cstddef>
#include <span>
#include <string>
#include <system_error>

namespace project::fs {

enum class OpenMode {
    kRead,
    kWriteTruncate,        // create or truncate
    kWriteCreateExclusive, // fail if the file exists
    kDirectory,            // open a directory, e.g. to sync it
};

struct OpenResult {
    int fd = -1;
    std::error_code error;
};

// Thin layer over POSIX file APIs. Every opened fd must be closed with Close.
class FileSystem {
public:
    virtual ~FileSystem() = default;

    virtual OpenResult Open(const std::string& path, OpenMode mode) = 0;
    virtual std::error_code Write(int fd, std::span<const std::byte> data) = 0;  // writes all bytes
    virtual std::error_code ReadAll(int fd, std::string& out) = 0;
    virtual std::error_code Sync(int fd) = 0;                                     // fsync
    virtual std::error_code Close(int fd) = 0;
    virtual std::error_code Rename(const std::string& from, const std::string& to) = 0;
    virtual std::error_code Remove(const std::string& path) = 0;
};

}  // namespace project::fs
