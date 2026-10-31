# OS 与 POSIX 接口

调用文件、内存映射、信号、进程、事件循环、时钟或线程相关的系统接口时阅读。以 Linux 为主，其他平台的差异单独标出。项目已有的系统调用封装优先；下面的规则同样适用于审查这些封装。

## 文件描述符

- 每个 fd 由一个 RAII owner 持有（见现代写法参考中的 `FileDescriptor`），所有路径都会关闭，且只关闭一次。
- 打开时总是带 `O_CLOEXEC`（`open`、`socket` 的 `SOCK_CLOEXEC`、`accept4`、`pipe2`、`eventfd` 的 `EFD_CLOEXEC`），避免在 `exec` 子进程时泄漏。
- `close` 失败时不重试：Linux 上 fd 已经释放，重试可能关掉别的线程刚打开的 fd。需要知道写入是否成功时，在 `close` 前 `fsync`。

## EINTR 与部分完成的读写

`read`/`write`/`pread`/`pwrite`/`send`/`recv` 可能只完成一部分，也可能被信号打断返回 `EINTR`。不能假设一次调用处理完全部数据：

```cpp
[[nodiscard]] std::error_code WriteAll(int fd, std::span<const std::byte> data) {
  while (!data.empty()) {
    const ssize_t written = ::write(fd, data.data(), data.size());
    if (written < 0) {
      if (errno == EINTR) continue;
      return {errno, std::system_category()};
    }
    if (written == 0) return std::make_error_code(std::errc::io_error);  // 避免死循环
    data = data.subspan(static_cast<std::size_t>(written));
  }
  return {};
}

// 读取恰好 buffer.size() 字节；提前遇到文件尾按短读错误处理。
[[nodiscard]] std::error_code ReadExactAt(int fd, std::span<std::byte> buffer, off_t offset) {
  while (!buffer.empty()) {
    const ssize_t got = ::pread(fd, buffer.data(), buffer.size(), offset);
    if (got < 0) {
      if (errno == EINTR) continue;
      return {errno, std::system_category()};
    }
    if (got == 0) return std::make_error_code(std::errc::io_error);  // 文件比预期短
    buffer = buffer.subspan(static_cast<std::size_t>(got));
    offset += got;
  }
  return {};
}
```

非阻塞 fd 上的 `EAGAIN`/`EWOULDBLOCK` 不是错误，而是“稍后再试”，由事件循环在 fd 可读写时继续，不能在上面的循环里忙等。

## 打开与创建文件

- 新建且不允许覆盖：`O_CREAT | O_EXCL`；权限显式写出（例如 `0644`，存放密钥的文件 `0600`），实际权限还受 `umask` 影响。
- 相对某个目录操作用 `openat` 一类接口，避免路径在检查与使用之间被替换；不跟随符号链接时加 `O_NOFOLLOW`。
- 临时文件用 `mkstemp` 或 Linux 的 `O_TMPFILE`，不要自己拼文件名再 `open`。
- `O_DIRECT` 要求缓冲区地址、文件偏移和长度按设备逻辑块大小对齐（常见 512 B 或 4 KiB）。对齐要求用 `statx` 的 `STATX_DIOALIGN`（Linux 6.1+）或块设备的 `BLKSSZGET` 查询，不写死。
- 持久化顺序（`fsync`、原子替换、目录同步）见存储与崩溃一致性参考。

## 内存映射

- `mmap` 的返回值与长度由一个 owner 持有，析构时 `munmap`。映射的生命周期独立于 fd：关闭 fd 后映射仍有效。
- `MAP_SHARED` 的修改会写回文件并对其他进程可见；`MAP_PRIVATE` 是写时复制。
- 文件被其他进程截断后访问映射超出文件末尾的部分会触发 `SIGBUS`。映射可能被截断的文件时，用文件锁或协议排除这种情况，而不是假设不会发生。
- 写回映射数据的持久化用 `msync(MS_SYNC)`；`madvise` 只是提示，不改变正确性。
- `mlock` 和大页受资源限制（`RLIMIT_MEMLOCK`、`/proc/sys/vm/nr_hugepages`），申请失败要有明确的错误而不是静默回退。

## 时钟与超时

| 用途 | 时钟 |
| --- | --- |
| 超时、截止时间、测量耗时 | `std::chrono::steady_clock`（对应 `CLOCK_MONOTONIC`），不会因校时而跳变 |
| 日志时间戳、与外部系统交换的时间 | `std::chrono::system_clock`（`CLOCK_REALTIME`） |

截止时间用绝对的 `steady_clock::time_point` 表示，在调用链中向下传递；每一层用剩余时间计算自己的超时，而不是各自重新开始计时。

## 信号

- 信号处理函数中只能调用异步信号安全的函数（`write`、`_exit` 等，见 `signal-safety(7)`）。不能加锁、分配内存、写日志或调用 `std::cout`。
- 需要处理 `SIGTERM`/`SIGINT` 做优雅退出时，在创建任何线程之前用 `pthread_sigmask` 屏蔽这些信号，再由一个专门线程用 `sigwait`，或用 `signalfd` 接入事件循环，然后通过正常的停止机制（`std::stop_source`、事件 fd）通知其他组件。
- 写已关闭的 socket 或管道会收到 `SIGPIPE`。网络程序忽略它（`signal(SIGPIPE, SIG_IGN)`）或在 `send` 时传 `MSG_NOSIGNAL`（Linux）/ 设置 `SO_NOSIGPIPE`（macOS），然后处理 `EPIPE`。

## 进程

- 多线程程序中优先用 `posix_spawn` 启动子进程。`fork` 之后、`exec` 之前，子进程只能调用异步信号安全的函数，因为其他线程持有的锁不会被释放。
- 回收子进程（`waitpid`），避免僵尸进程；Linux 5.3+ 可以用 `pidfd_open` 把子进程退出接入事件循环，并避免 pid 复用造成的误判。
- 不在库代码中调用 `exit`；终止进程的决定属于程序入口。

## 事件循环与异步 I/O

- `epoll` 的边缘触发模式要求每次都读写到 `EAGAIN` 为止，否则会丢失事件；水平触发更不容易出错。
- 线程间唤醒用 `eventfd`，定时器用 `timerfd`，信号用 `signalfd`，都可以统一放进同一个 `epoll`。
- `io_uring`（通过 liburing）的提交与完成是异步的：缓冲区、注册的文件和缓冲区必须在对应的完成事件（CQE）返回之前保持有效。取消请求也要等到完成事件，不能在提交取消后立即释放缓冲区。

## 资源与线程

- 打开文件数受 `RLIMIT_NOFILE` 限制；服务启动时检查并在日志中记录实际值，而不是在运行中随机失败。
- 线程命名（`pthread_setname_np`）便于调试。线程亲和性与 NUMA 绑定（`pthread_setaffinity_np`、libnuma）属于部署决策，放在配置中，不写死在库里。
- 读取 `/proc`、`/sys` 时按文本格式容错解析，内核版本不同字段可能不同。
