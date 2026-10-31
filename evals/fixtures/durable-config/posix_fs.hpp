#pragma once

#include <fcntl.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>

#include "fs.hpp"

namespace project::fs {

class PosixFileSystem final : public FileSystem {
public:
    OpenResult Open(const std::string& path, OpenMode mode) override {
        int flags = O_CLOEXEC;
        switch (mode) {
            case OpenMode::kRead: flags |= O_RDONLY; break;
            case OpenMode::kWriteTruncate: flags |= O_WRONLY | O_CREAT | O_TRUNC; break;
            case OpenMode::kWriteCreateExclusive: flags |= O_WRONLY | O_CREAT | O_EXCL; break;
            case OpenMode::kDirectory: flags |= O_RDONLY | O_DIRECTORY; break;
        }
        const int fd = ::open(path.c_str(), flags, 0644);
        if (fd < 0) return {-1, LastError()};
        return {fd, {}};
    }

    std::error_code Write(int fd, std::span<const std::byte> data) override {
        while (!data.empty()) {
            const ssize_t written = ::write(fd, data.data(), data.size());
            if (written < 0) {
                if (errno == EINTR) continue;
                return LastError();
            }
            if (written == 0) return std::make_error_code(std::errc::io_error);
            data = data.subspan(static_cast<std::size_t>(written));
        }
        return {};
    }

    std::error_code ReadAll(int fd, std::string& out) override {
        out.clear();
        char buffer[4096];
        while (true) {
            const ssize_t got = ::read(fd, buffer, sizeof(buffer));
            if (got < 0) {
                if (errno == EINTR) continue;
                return LastError();
            }
            if (got == 0) return {};
            out.append(buffer, static_cast<std::size_t>(got));
        }
    }

    std::error_code Sync(int fd) override { return ::fsync(fd) == 0 ? std::error_code{} : LastError(); }
    std::error_code Close(int fd) override { return ::close(fd) == 0 ? std::error_code{} : LastError(); }

    std::error_code Rename(const std::string& from, const std::string& to) override {
        return ::rename(from.c_str(), to.c_str()) == 0 ? std::error_code{} : LastError();
    }

    std::error_code Remove(const std::string& path) override {
        return ::unlink(path.c_str()) == 0 ? std::error_code{} : LastError();
    }

private:
    static std::error_code LastError() { return {errno, std::system_category()}; }
};

}  // namespace project::fs
