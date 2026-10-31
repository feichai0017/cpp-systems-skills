# 安全与加固

处理不可信输入（网络、文件、命令行、跨进程消息）、文件权限、密钥、随机数，或配置编译加固选项时阅读。项目的安全要求与审计流程优先。

## 不可信输入

- 在信任边界（网络接收、文件解析、IPC、插件接口）集中校验，校验后用类型或结构表达“已校验”，内部代码不再重复检查。
- 所有来自输入的长度、偏移、计数、索引都要检查上限和溢出，按溢出安全的方式比较（见内存与对象模型参考的 `RangeFits`）。
- 递归解析设置最大深度；集合设置最大元素数；整体请求设置最大字节数，防止资源耗尽。
- 解析失败返回明确错误，不要部分应用输入、继续处理剩余字段。

## 字符串与格式化

- 不要把外部字符串当作格式串：`printf(user_text)`、`fmt::format(fmt::runtime(user_text))` 都会把输入当作格式解释。`std::format`/`fmt::format` 的格式串在编译期检查，应保持为字面量。
- 不用 `strcpy`、`sprintf`、`gets`；需要 C 接口时用带长度的版本并检查截断。

## 文件系统

- 检查与使用之间的竞争（TOCTOU）：先 `open`，再对 fd `fstat`；不要先 `stat` 路径再 `open`。处理不可信路径时用 `openat` 系列、`O_NOFOLLOW`，并限制在预期目录内。
- 临时文件用 `mkstemp` 或 `O_TMPFILE`；保存密钥的文件权限为 `0600`，并在创建时设置，而不是创建后再 `chmod`。

## 密钥与随机数

- 密钥不写入日志、错误信息和 core dump 能轻易读取的长期缓冲区；用完后用 `explicit_bzero` 或 `OPENSSL_cleanse` 清除，普通 `memset` 可能被编译器优化掉。
- 安全相关的随机数用 `getrandom(2)` 或密码学库（`RAND_bytes`）。`std::random_device` 不保证具备密码学强度，`std::mt19937` 只用于模拟和测试。
- 比较 MAC、令牌等秘密值用常量时间比较（`CRYPTO_memcmp`），不用 `memcmp` 或 `==`。
- 加密、签名、TLS 使用成熟库，不自行实现算法或协议。

## 权限

- 进程以完成任务所需的最小权限运行；需要特权的操作（绑定低端口、`mlock`、RDMA 设备访问）通过能力（capabilities）或部署配置授予，而不是以 root 运行整个服务。
- 不在库中调用 `setuid`/`setgid`；这类决定属于部署与入口程序。

## 编译加固选项

在项目的 CI 或发布构建中按需启用（GCC/Clang）：

| 选项 | 作用 |
| --- | --- |
| `-D_FORTIFY_SOURCE=2`（或 `3`） | 对已知大小的缓冲区做运行时检查；需要开启优化（`-O1` 以上） |
| `-D_GLIBCXX_ASSERTIONS` | libstdc++ 的下标与前置条件检查；libc++ 对应 `_LIBCPP_HARDENING_MODE`（LLVM 18+） |
| `-fstack-protector-strong` | 栈溢出检测 |
| `-fstack-clash-protection` | 防止栈与其他内存区域碰撞 |
| `-fcf-protection`（x86） | 控制流保护 |
| `-fPIE -pie`、`-Wl,-z,relro,-z,now` | 地址随机化与只读重定位表 |
| `-Wformat -Wformat-security` | 格式串误用的编译期警告 |

具体组合与平台差异参考 [OpenSSF 编译器加固指南](https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html)。加固选项会带来少量性能开销，性能对比时保持两边一致。

## 测试

- 解析器、协议解码和文件格式读取是模糊测试的首要目标（libFuzzer 配合 ASan/UBSan），见 `cpp-validation` 技能的测试策略。
- 为超长输入、负数与极大值、截断数据、嵌套过深等边界编写回归测试。
