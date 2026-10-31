#pragma once

#include <span>
#include <string>
#include <string_view>
#include <system_error>

#include "fs.hpp"

namespace project {

// Replaces the configuration stored at `path` with `text`.
inline std::error_code SaveConfig(fs::FileSystem& fs, const std::string& path, std::string_view text) {
    const fs::OpenResult file = fs.Open(path, fs::OpenMode::kWriteTruncate);
    if (file.error) return file.error;
    const std::error_code error = fs.Write(file.fd, std::as_bytes(std::span(text)));
    fs.Close(file.fd);
    return error;
}

inline std::error_code LoadConfig(fs::FileSystem& fs, const std::string& path, std::string& text) {
    const fs::OpenResult file = fs.Open(path, fs::OpenMode::kRead);
    if (file.error) return file.error;
    const std::error_code error = fs.ReadAll(file.fd, text);
    fs.Close(file.fd);
    return error;
}

}  // namespace project
