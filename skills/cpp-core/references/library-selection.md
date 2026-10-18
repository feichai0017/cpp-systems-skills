# 基础库选型

仅在现有能力有缺口、需要选择或替换基础组件时使用。先查仓库、已引入依赖和当前标准库；满足合同就停止选型。下面是候选入口，不是要求全部安装的工具栈。

资料核对日期：2026-10-18。具体模块、语言标准和构建条件按目标工程固定版本核对；上游功能与 benchmark 不构成本项目的正确性或性能证据。

## 按职责选择

| 需求 | 候选与入口 | 使用前确认 |
| --- | --- | --- |
| 格式化 | [{fmt}](https://fmt.dev/latest/) | 当前标准库格式化能力是否已足够；沿用已有格式化接口与错误策略，避免只做转发的包装层 |
| 日志 | [spdlog](https://github.com/gabime/spdlog)、[异步日志](https://github.com/gabime/spdlog/wiki/Asynchronous-logging) | 是否已有日志体系；多/单线程 logger、sink、异步队列的满载策略和退出 flush 合同，避免并行引入第二套日志 |
| 哈希容器与通用工具 | [Abseil 指南](https://abseil.io/docs/cpp/guides/)、[容器](https://abseil.io/docs/cpp/guides/container) | `flat_hash_map` / `node_hash_map` 的地址与迭代器稳定性；字符串、时间等工具按已启用模块复用。已有错误框架时不另引入 `Status` / `StatusOr` |
| 网络、定时器与异步 I/O | [Boost.Asio](https://www.boost.org/doc/libs/latest/doc/html/boost_asio.html)、[异步模型](https://www.boost.org/doc/libs/latest/doc/html/boost_asio/overview.html) | 执行器、回调线程、buffer 寿命、取消与实际完成；已有运行时能完成任务时继续复用，不为一个接口另建事件循环 |
| 共享内存地址表示与基础设施 | [Boost.Interprocess](https://www.boost.org/doc/libs/latest/doc/html/interprocess.html)、[`offset_ptr` 文档](https://www.boost.org/doc/libs/latest/doc/html/interprocess/offset_ptr.html)与[源码](https://github.com/boostorg/interprocess/blob/develop/include/boost/interprocess/offset_ptr.hpp) | 不同映射地址、布局、allocator 和同步前提；对象相对偏移不等于 region-relative offset，进程死亡恢复与协议版本仍由项目定义 |
| 资源 guard 与并发组件 | [Folly 组件索引](https://github.com/facebook/folly/blob/main/folly/docs/Overview.md)、[`ScopeGuard`](https://github.com/facebook/folly/blob/main/folly/ScopeGuard.h) | 回滚 guard 的构造、移动、dismiss 和析构；`MPMCQueue` 等组件的容量、生产者/消费者模型与阻塞行为，不能只凭“无锁/高性能”选型 |
| 行为测试 | [GoogleTest](https://github.com/google/googletest/blob/main/docs/primer.md) | 沿用已有框架；用行为断言和 fixture 覆盖真实合同，避免为局部修改引入第二套测试体系 |
| 局部性能测量 | [Google Benchmark](https://github.com/google/benchmark/blob/main/docs/user_guide.md) | 预热、重复、输入规模、分配成本与编译器优化；异步任务计时覆盖实际完成，端到端收益另测 |

## 容易改变合同的选择

- **容器替换**：查调用方是否保存元素地址、引用或迭代器。Abseil `flat_hash_map` / `flat_hash_set` rehash 会使元素地址失效，`node_hash_map` / `node_hash_set` 可以保持元素地址但 rehash 仍使迭代器失效；不能把这些容器当作标准无序容器的无条件替代。
- **依赖与 ABI**：确认模块实际链接到目标，并统一版本和相关构建配置。[Abseil](https://abseil.io/about/compatibility) 和 [Folly](https://github.com/facebook/folly#build-notes) 均不承诺不同版本/提交间的 ABI 兼容；共享库、插件和动态加载场景不能默认混用二进制。
- **异步资源**：取消请求不自动证明最后一次 buffer 访问已经结束；采用库时仍要把 owner、借用和完成通知接入本项目的关闭协议。
- **跨进程数据**：区分进程本地句柄与共享布局；偏移指针只解决其定义的寻址问题，不能代替 generation、访问保护、回收确认或崩溃恢复。
- **引入成本**：Folly、Asio 等模块需要与工具链、依赖图及运行时相容。不要为一个局部 helper 引入整套框架，也不要未经核对就摘抄内部实现。

选择结果只需说明实际采用的模块/符号、版本依据、关键前提及需要验证的合同。依赖足够时直接调用；确有错误转换、资源持有或平台隔离职责时再写适配层。

若只是学习机制或代码组织，使用 [项目与实现参考](project-references.md)。复制适配源码、只参考设计与引入依赖的检查方法见 [复用与源码参考](reuse-and-precedents.md)。
