#pragma once

// Reviewer-only: the reference SaveConfig, built with -DMUTANT=n to ignore one failure
// (1 Write, 2 file Sync, 3 Rename, 4 directory Sync). A workspace's own tests detect a
// failure path when they fail against the mutant that ignores it.

#include <cstddef>
#include <span>
#include <string>
#include <string_view>
#include <system_error>

#include "fs.hpp"

#ifndef MUTANT
#define MUTANT 0
#endif

namespace project {

inline std::error_code SaveConfig(fs::FileSystem& fs, const std::string& path, std::string_view text) {
    const std::string temporary = path + ".tmp";
    const fs::OpenResult file = fs.Open(temporary, fs::OpenMode::kWriteTruncate);
    if (file.error) return file.error;
    std::error_code error = fs.Write(file.fd, std::as_bytes(std::span(text)));
    if (MUTANT == 1) error = {};
    if (!error) {
        error = fs.Sync(file.fd);
        if (MUTANT == 2) error = {};
    }
    fs.Close(file.fd);
    if (!error) {
        error = fs.Rename(temporary, path);
        if (MUTANT == 3) error = {};
    }
    if (error) {
        fs.Remove(temporary);
        return error;
    }

    const std::size_t slash = path.rfind('/');
    const fs::OpenResult directory =
        fs.Open(slash == std::string::npos ? "." : path.substr(0, slash + 1), fs::OpenMode::kDirectory);
    if (directory.error) return directory.error;
    error = fs.Sync(directory.fd);
    if (MUTANT == 4) error = {};
    fs.Close(directory.fd);
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
