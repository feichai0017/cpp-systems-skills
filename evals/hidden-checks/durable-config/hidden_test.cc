// Reviewer-only check: records FileSystem calls made by SaveConfig and injects failures.
#include "config_store.hpp"
#include "posix_fs.hpp"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <map>
#include <string>
#include <vector>

namespace {

struct Op {
    std::string kind;
    std::string path;
    project::fs::OpenMode mode = project::fs::OpenMode::kRead;
    std::string to;
};

class RecordingFileSystem final : public project::fs::FileSystem {
public:
    int fail_sync_of_file = 0;   // 1 = fail the first Sync on a regular file
    bool fail_write_enospc = false;
    bool fail_rename = false;
    bool fail_directory_sync = false;
    bool keep_removed_files = false;  // Remove succeeds without unlinking, as when a crash skips cleanup

    project::fs::OpenResult Open(const std::string& path, project::fs::OpenMode mode) override {
        ops.push_back({"open", path, mode, ""});
        auto result = real_.Open(path, mode);
        if (!result.error) { fd_path_[result.fd] = path; fd_mode_[result.fd] = mode; ++opens; }
        return result;
    }
    std::error_code Write(int fd, std::span<const std::byte> data) override {
        ops.push_back({"write", fd_path_[fd], fd_mode_[fd], ""});
        if (fail_write_enospc) {
            // Simulate a partial write followed by ENOSPC.
            (void)real_.Write(fd, data.first(data.size() / 2));
            return std::make_error_code(std::errc::no_space_on_device);
        }
        return real_.Write(fd, data);
    }
    std::error_code ReadAll(int fd, std::string& out) override { return real_.ReadAll(fd, out); }
    std::error_code Sync(int fd) override {
        const bool directory = fd_mode_[fd] == project::fs::OpenMode::kDirectory;
        ops.push_back({directory ? "sync-dir" : "sync-file", fd_path_[fd], fd_mode_[fd], ""});
        if (!directory && fail_sync_of_file > 0 && --fail_sync_of_file == 0) return std::make_error_code(std::errc::io_error);
        if (directory && fail_directory_sync) return std::make_error_code(std::errc::io_error);
        return real_.Sync(fd);
    }
    std::error_code Close(int fd) override {
        ops.push_back({"close", fd_path_[fd], fd_mode_[fd], ""});
        ++closes;
        return real_.Close(fd);
    }
    std::error_code Rename(const std::string& from, const std::string& to) override {
        ops.push_back({"rename", from, project::fs::OpenMode::kRead, to});
        if (fail_rename) return std::make_error_code(std::errc::cross_device_link);
        return real_.Rename(from, to);
    }
    std::error_code Remove(const std::string& path) override {
        ops.push_back({"remove", path, project::fs::OpenMode::kRead, ""});
        if (keep_removed_files) return {};
        return real_.Remove(path);
    }

    std::vector<Op> ops;
    int opens = 0;   // fds may be reused, so count opens rather than distinct fds
    int closes = 0;

private:
    project::fs::PosixFileSystem real_;
    std::map<int, std::string> fd_path_;
    std::map<int, project::fs::OpenMode> fd_mode_;
};

int failures = 0;
void Expect(bool ok, const char* what) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++failures;
}

// Soft criteria: reported, not counted as failures.
void Prefer(bool ok, const char* what) { std::printf("%s %s\n", ok ? "HIT" : "MISS", what); }

std::string Read(const std::string& path) {
    project::fs::PosixFileSystem fs;
    std::string text;
    (void)project::LoadConfig(fs, path, text);
    return text;
}

int Index(const std::vector<Op>& ops, auto predicate) {
    for (int i = 0; i < static_cast<int>(ops.size()); ++i) if (predicate(ops[i])) return i;
    return -1;
}

}  // namespace

int main() {
    namespace stdfs = std::filesystem;
    const stdfs::path dir = stdfs::temp_directory_path() / "durable_config_hidden";
    stdfs::remove_all(dir);
    stdfs::create_directories(dir);
    const std::string target = (dir / "service.conf").string();
    {
        project::fs::PosixFileSystem fs;
        (void)project::SaveConfig(fs, target, "old=1\n");
    }

    // 1. Success path ordering.
    RecordingFileSystem fs;
    const std::error_code ok = project::SaveConfig(fs, target, "new=2\n");
    Expect(!ok, "save succeeds");
    Expect(Read(target) == "new=2\n", "target holds the new content");
    const auto& ops = fs.ops;
    const bool target_opened_for_write = Index(ops, [&](const Op& op) {
        return op.kind == "open" && op.path == target && op.mode != project::fs::OpenMode::kRead &&
               op.mode != project::fs::OpenMode::kDirectory; }) >= 0;
    Expect(!target_opened_for_write, "target is never opened for writing in place");
    const int rename_at = Index(ops, [&](const Op& op) { return op.kind == "rename" && op.to == target; });
    Expect(rename_at >= 0, "new content is renamed onto the target");
    if (rename_at >= 0) {
        const std::string temp = ops[rename_at].path;
        Expect(stdfs::path(temp).parent_path() == dir, "temporary file is in the target directory");
        const int write_at = Index(ops, [&](const Op& op) { return op.kind == "write" && op.path == temp; });
        const int sync_at = Index(ops, [&](const Op& op) { return op.kind == "sync-file" && op.path == temp; });
        Expect(write_at >= 0 && sync_at > write_at && sync_at < rename_at, "temporary file is synced after writing and before rename");
        int dir_sync_at = -1;
        for (int i = rename_at + 1; i < static_cast<int>(ops.size()); ++i) {
            std::error_code same_error;
            // "dir", "dir/" and "dir/." all name the target directory.
            if (ops[i].kind == "sync-dir" && stdfs::equivalent(ops[i].path, dir, same_error)) dir_sync_at = i;
        }
        Expect(dir_sync_at > rename_at, "directory is synced after rename");
    }
    Expect(fs.closes == fs.opens, "every opened fd is closed");

    // 2. fsync failure on the temporary file.
    RecordingFileSystem failing_sync;
    failing_sync.fail_sync_of_file = 1;
    const std::error_code sync_error = project::SaveConfig(failing_sync, target, "broken=3\n");
    Expect(static_cast<bool>(sync_error), "sync failure is reported");
    Expect(Read(target) == "new=2\n", "target unchanged after sync failure");
    // After a failed fsync the kernel may have dropped the dirty pages; a second fsync can succeed
    // without the data reaching the disk.
    const auto file_syncs = std::count_if(failing_sync.ops.begin(), failing_sync.ops.end(),
                                          [](const Op& op) { return op.kind == "sync-file"; });
    Prefer(file_syncs == 1, "a failed Sync is not retried");

    // 3. ENOSPC during write.
    RecordingFileSystem full_disk;
    full_disk.fail_write_enospc = true;
    const std::error_code write_error = project::SaveConfig(full_disk, target, "partial=4\n");
    Expect(write_error == std::errc::no_space_on_device, "write failure is reported as is");
    Expect(Read(target) == "new=2\n", "target unchanged after write failure");
    Expect(full_disk.closes == full_disk.opens, "fds closed on the failure path");

    // 4. Rename failure.
    RecordingFileSystem failing_rename;
    failing_rename.fail_rename = true;
    const std::error_code rename_error = project::SaveConfig(failing_rename, target, "moved=5\n");
    Expect(rename_error == std::errc::cross_device_link, "rename failure is reported as is");
    Expect(Read(target) == "new=2\n", "target unchanged after rename failure");
    Expect(failing_rename.closes == failing_rename.opens, "fds closed after rename failure");

    int leftovers = 0;
    for (const auto& entry : stdfs::directory_iterator(dir)) {
        if (entry.path() != stdfs::path(target)) ++leftovers;
    }
    Expect(leftovers == 0, "no temporary files are left behind after failures");

    // 5. Directory sync failure: the new content is in place but may not survive a power loss.
    RecordingFileSystem failing_directory;
    failing_directory.fail_directory_sync = true;
    const std::error_code directory_error = project::SaveConfig(failing_directory, target, "dir=6\n");
    Prefer(static_cast<bool>(directory_error), "directory sync failure is reported");
    Expect(failing_directory.closes == failing_directory.opens, "fds closed after directory sync failure");

    // 6. A crash between creating and removing the temporary file leaves it behind; the next save
    // must still succeed.
    RecordingFileSystem crashed;
    crashed.fail_sync_of_file = 1;
    crashed.keep_removed_files = true;
    (void)project::SaveConfig(crashed, target, "lost=7\n");
    project::fs::PosixFileSystem posix;
    const std::error_code after_crash = project::SaveConfig(posix, target, "after=8\n");
    Expect(!after_crash && Read(target) == "after=8\n", "save succeeds after a crash left a temporary file");

    stdfs::remove_all(dir);
    std::printf(failures == 0 ? "hidden durability: PASS\n" : "hidden durability: %d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
