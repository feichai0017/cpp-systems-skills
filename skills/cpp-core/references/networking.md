# 网络与 RPC

编写 socket、协议编解码、RPC 客户端/服务端或跨节点数据传输时阅读。项目已有的网络运行时（gRPC、Asio、Seastar、自研框架）优先；RDMA 与设备 DMA 的完成与寿命合同属于 `cpp-lifetime` 技能的跨边界参考。

## Socket 基础

- socket 由 RAII owner 持有。创建时带 `SOCK_CLOEXEC`，服务端 `accept4(..., SOCK_NONBLOCK | SOCK_CLOEXEC)`。
- 服务端监听前设置 `SO_REUSEADDR`，避免重启时被 `TIME_WAIT` 阻塞；多个进程/线程分担同一端口时才用 `SO_REUSEPORT`。
- 低延迟的请求/响应协议设置 `TCP_NODELAY`；批量传输保持默认的 Nagle 行为或自行合并写入。
- 忽略或屏蔽 `SIGPIPE`（见 OS 接口参考），把对端关闭当作 `EPIPE`/`ECONNRESET` 处理。
- 发送和接收都可能只完成一部分；阻塞 socket 用循环，非阻塞 socket 交给事件循环在可写/可读时继续。

## 消息边界与解码

TCP 是字节流，没有消息边界。协议必须自带边界，常见做法是固定长度的头部加长度前缀：

```cpp
inline constexpr std::size_t kHeaderBytes = 8;
inline constexpr std::uint32_t kMaxFrameBytes = 16u << 20;

struct FrameHeader {
  std::uint32_t type;
  std::uint32_t payload_bytes;
};

// 线上格式固定为小端，与主机字节序无关。
[[nodiscard]] inline std::uint32_t LoadLittleEndian32(std::span<const std::byte, 4> bytes) {
  return std::to_integer<std::uint32_t>(bytes[0]) |
         std::to_integer<std::uint32_t>(bytes[1]) << 8 |
         std::to_integer<std::uint32_t>(bytes[2]) << 16 |
         std::to_integer<std::uint32_t>(bytes[3]) << 24;
}

[[nodiscard]] inline Result<FrameHeader> DecodeHeader(std::span<const std::byte, kHeaderBytes> bytes) {
  const FrameHeader header{
      .type = LoadLittleEndian32(bytes.first<4>()),
      .payload_bytes = LoadLittleEndian32(bytes.last<4>()),
  };
  if (header.payload_bytes > kMaxFrameBytes) return Status::InvalidArgument("frame too large");
  return header;
}
```

- 长度字段来自对端，属于不可信输入：先检查上限再分配内存，防止一个恶意长度耗尽内存。
- 字节序在协议中写明。用移位组装（如上）最可移植；C++20 的 `std::endian` 可判断主机字节序，C++23 的 `std::byteswap` 可做转换。不要直接把结构体 `memcpy` 到线上：填充字节、对齐和字节序都会变成协议的一部分。
- 版本或类型字段放在头部，未知类型按协议规定拒绝或跳过，不能当作已知类型解析。

## 背压与流量控制

- 发送队列、接收缓冲和待处理请求都要有上限。达到上限时按协议拒绝、阻塞生产者或丢弃可丢弃的数据，不能无界增长。
- 慢消费者不能拖垮整个服务：每个连接的缓冲独立计量，超过限制的连接被断开或限速。
- 记录队列深度和拒绝次数的指标，便于发现背压。

## 超时、截止时间与取消

- 每个请求携带绝对截止时间（`steady_clock` 时间点或协议中的剩余时长），下游调用用剩余时间，而不是各自固定的超时。
- 超时只表示调用方不再等待。对端可能仍在处理或已经完成；释放请求相关资源前，确认传输层不会再写入这些缓冲区。
- 取消要沿调用链传播（gRPC 的 `ServerContext::IsCancelled`/`TryCancel`、Asio 的 cancellation slot、`std::stop_token`），被取消的下游请求也要被取消或标记为无需结果。

## 重试与幂等

- 只重试可重试的错误（连接失败、对端过载、超时），并使用有上限的指数退避加随机抖动。
- 写操作重试必须幂等，或携带请求 id 让服务端去重；“没有收到响应”不能被当作“没有执行”。
- 设置全局重试预算，避免故障时重试放大流量。

## 连接生命周期

- 区分连接建立、可用、正在关闭和已关闭；关闭时先停止接受新请求，再等待或取消在途请求，最后释放连接。
- 半关闭（`shutdown(SHUT_WR)`）用于告知对端“不会再发送”，仍可以继续接收。
- 长连接用应用层心跳或 `SO_KEEPALIVE` 检测失联，心跳超时时间写进配置。

## 序列化与兼容演进

- protobuf：字段编号一旦发布就不能复用或改类型；删除的字段编号和名称放进 `reserved`；新字段要能在旧版本中被忽略。需要区分“未设置”和“默认值”时用 `optional`。
- FlatBuffers / Cap'n Proto 支持零拷贝读取，但读取到的视图借用接收缓冲区，缓冲区必须活得比所有视图久。
- 自定义二进制格式写明版本号、字节序、对齐和长度上限，并为每种解析错误提供测试。

## 零拷贝与批量

- `sendfile`、`splice` 可以避免用户态拷贝；`MSG_ZEROCOPY`（Linux 4.14+）需要等待完成通知后才能复用缓冲区，小消息上收益通常为负。
- 合并小写入（`writev`/`sendmsg` 的 iovec）比多次 `send` 更省系统调用。
- 任何零拷贝方案都改变了缓冲区的寿命合同，按 `cpp-lifetime` 的方法检查发布、使用与回收。

## TLS 与安全

- 用 OpenSSL、BoringSSL 或项目已有的 TLS 实现，不自行实现加密协议。证书校验和主机名校验默认开启。
- 认证信息、令牌不写入日志。所有来自网络的长度、偏移、计数都按不可信输入校验。
