# 存储与崩溃一致性

编写需要在进程崩溃或掉电后仍然正确的文件写入、日志（WAL）、元数据或磁盘格式时阅读。缓存类数据（重启后可丢弃）不需要持久化保证，但仍需要防止读到半写的数据。

## 先说清持久化合同

每个写入路径都要明确：调用返回时，数据是“已交给内核”（页缓存）、“已落盘”，还是“只在内存中”。接口名称和文档写清楚完成点，例如 `Append` 只写入页缓存，`Sync` 才保证落盘。

## 写入与 fsync

- `write` 成功只代表数据进了页缓存。需要落盘时调用 `fsync`（数据和元数据）或 `fdatasync`（只保证数据和读取所需的元数据，例如文件长度）。
- 新建文件或重命名后，还要对**所在目录**调用 `fsync`，否则目录项可能在掉电后丢失。
- `fsync` 失败后不能简单重试：Linux 可能已经丢弃了脏页并清除了错误状态，再次 `fsync` 返回成功也不代表数据已落盘。把 `fsync` 失败当作该文件的数据可能已丢失处理：上报错误，从日志或副本恢复，或终止。
- `O_DIRECT` 绕过页缓存，但不替代 `fsync`：设备自身的写缓存仍需要刷新（`fsync`/`fdatasync` 会发出刷新命令），也可用 `O_DSYNC` 让每次写入同步完成。
- 空间预分配（`fallocate`）可以提前发现 `ENOSPC`，避免在关键写入中途失败。

## 原子替换文件

更新配置、索引或快照文件时，写入临时文件再重命名，读者要么看到旧文件，要么看到完整的新文件：

```cpp
[[nodiscard]] Status AtomicReplaceFile(const std::filesystem::path& target,
                                      std::span<const std::byte> contents) {
  const std::filesystem::path dir = target.parent_path();
  const std::filesystem::path temp = target.string() + ".tmp";

  FileDescriptor file(::open(temp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644));
  if (!file.IsValid()) return Status::FromSystemError(LastSystemError(), "open " + temp.string());
  if (auto error = WriteAll(file.Get(), contents)) return Status::FromSystemError(error, "write");
  if (::fsync(file.Get()) != 0) return Status::FromSystemError(LastSystemError(), "fsync file");
  file = FileDescriptor();  // 关闭临时文件

  if (::rename(temp.c_str(), target.c_str()) != 0) {
    return Status::FromSystemError(LastSystemError(), "rename");
  }

  FileDescriptor directory(::open(dir.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  if (!directory.IsValid()) return Status::FromSystemError(LastSystemError(), "open dir");
  if (::fsync(directory.Get()) != 0) return Status::FromSystemError(LastSystemError(), "fsync dir");
  return Status::Ok();
}
```

- 临时文件必须与目标在同一文件系统（通常同一目录），`rename` 才是原子的。
- 多个进程可能同时写同一目标时，临时文件名要唯一（加 pid 或随机后缀），或用文件锁串行化。
- 启动时清理遗留的临时文件。

## 预写日志（WAL）

- 每条记录包含长度、序列号和校验和（例如 CRC32C），按追加方式写入。
- 恢复时顺序读取，遇到第一条长度越界、校验和不匹配或序列号不连续的记录就停止，把它及之后的内容视为未完成的写入（撕裂写）。不要跳过坏记录继续读后面的内容，除非格式明确支持。
- 提交点明确：记录在 `fsync` 返回后才算持久化；向调用方确认提交前必须完成这一步，或者按批次合并 `fsync`（group commit）并在批次落盘后统一确认。
- 检查点或快照完成并落盘后，才能截断已被覆盖的日志。

## 磁盘格式

- 文件以魔数、格式版本和特性标志开头；读取时拒绝不认识的主版本，按规则处理不认识的特性。
- 整数使用固定宽度和固定字节序（通常小端），按字段编码，不直接把结构体的内存表示写入文件。确需直接映射结构体时，用 `static_assert` 固定 `sizeof`、`alignof`、`std::is_trivially_copyable_v` 和字段偏移，并写明字节序。
- 每个块或记录带校验和，读取时验证；校验和失败是数据损坏，不是“没有数据”。
- 偏移和长度来自文件内容时属于不可信输入，按文件实际大小检查边界与溢出。

## 读取路径

- `pread` 可能短读；读取固定长度的结构时，要么读满，要么报告文件截断（见 OS 接口参考的 `ReadExactAt`）。
- 用 `mmap` 读取时，文件被截断会触发 `SIGBUS`；只映射不会被其他进程截断的文件，或用锁和协议保护。
- 基准测试读路径时区分页缓存命中与真实磁盘读取，必要时用 `O_DIRECT` 或在测试前清空缓存，并记录所用方式。

## 锁与并发访问

- 进程间互斥用 `flock` 或 `fcntl` 记录锁，或者一个独立的锁文件；锁随 fd 关闭而释放，进程崩溃后自动解除。
- `fcntl` 锁属于进程，同一进程关闭该文件的任意一个 fd 都会释放锁；Linux 的 OFD 锁（`F_OFD_SETLK`）没有这个问题。

## 验证

- 崩溃一致性测试：在写入、`fsync`、`rename` 的各个点注入失败或强制终止进程（`kill -9`），然后验证恢复结果只能是旧状态或新状态。
- 测试磁盘写满（`ENOSPC`）、权限错误和短读路径。
- 掉电级别的验证需要块设备层的工具（例如带故障注入的设备映射），与进程级测试分开报告覆盖范围。
