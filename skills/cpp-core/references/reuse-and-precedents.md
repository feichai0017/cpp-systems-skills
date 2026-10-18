# 复用与源码参考

在新增基础组件、复杂机制或现有依赖不足时使用。查找结果必须影响实现选择；不为小修改制造研究流程。

## 先查当前工程

1. 用 `rg` 搜职责、符号、错误信息和类似调用，读最近的实现与测试。名称不同的代码也可能承担同一职责。
2. 查构建清单、锁文件、vendor 目录和实际 include，确认库版本、已启用模块与编译宏。包已安装不等于目标已经链接它。
3. 对照所需合同：返回与错误语义、owner/borrow、回调线程、取消/关闭、容量与复杂度。优先扩展现有合适组件的小缺口。
4. 本地能力足够就停止研究。记录实际采用的符号即可；不要求每次列候选表。

## 需要外部参考时

- 根据问题检索机制和失败模式，例如“bounded queue shutdown”“shared memory relative offset”“permit cancellation”，不要只搜“best C++ library”。
- 先看少量最相关的成熟实现，再读调用方、关键测试和必要的变更记录。README 和星数只能帮助定位，不能证明合同或性能。
- 从官方仓库核对代码。记录实际读过的 commit/tag、文件/符号、采用的机制及本地差异；没有读到的实现不要写成已验证依据。
- 核对语言标准、工具链、异常/RTTI、线程/进程模型、ABI、allocator、平台与依赖规模。最新文档中的 API 未必存在于项目固定版本。
- 直接调用库、引入新依赖、复制适配源码、只参考设计是不同动作。比较总成本；不要为一个局部能力引入整个运行时。
- 复制代码前核对对应版本的许可、署名与修改标记要求。仅借鉴机制时，用本项目约定实现缺失部分，不复制无关层次或内部接口。
- 候选不适用时说明具体前提差异，继续已有可验证路径。无法联网不阻止本地实现，但应说明外部参考尚未核验。

需要比较时，用短表记录：

| 候选与版本/符号 | 所需能力是否满足 | 前提差异与成本 | 选择 |
| --- | --- | --- | --- |
| 实际读过的来源 | 具体合同 | 本地限制 | 调用 / 引入 / 参考适配 / 不采用 |

完成选择后进入实现；只有新证据表明候选不适用时才扩大搜索。

## 按问题选择入口

一般 C++ 工程规范以 [DuckDB](duckdb.md) 为主要外部参考；下面是特定机制的补充入口。选择“规范样例”与引入某个库是不同决定，项目已有实现仍优先。

以下链接用于定位机制，不是指定依赖清单。固定到本次实际核对的版本后再引用，不能据此宣称某实现更快。

| 问题 | 源码入口 | 可借鉴内容与边界 |
| --- | --- | --- |
| 资源释放和失败回滚 | [Folly ScopeGuard](https://github.com/facebook/folly/blob/main/folly/ScopeGuard.h) | 构造、移动、dismiss 与析构；已有库可用时直接复用 |
| 不同进程的映射地址 | [Boost.Interprocess offset_ptr](https://github.com/boostorg/interprocess/blob/develop/include/boost/interprocess/offset_ptr.hpp) | 相对地址与布局假设；对象相对偏移不等于 region-relative offset |
| 分片服务的所有权与关闭 | [Seastar sharded](https://github.com/scylladb/seastar/blob/master/include/seastar/core/sharded.hh) | 分片创建、跨分片调用、停止；其 runtime 和线程模型不能默认移植 |
| 可跨任务移动的额度 | [Tokio semaphore](https://github.com/tokio-rs/tokio/blob/master/tokio/src/sync/semaphore.rs) | `OwnedSemaphorePermit` 持有额度并在 Drop 归还；不等于远端 lease 已获得 release ACK |
| 读保护和延迟回收 | [Crossbeam epoch Guard](https://github.com/crossbeam-rs/crossbeam/blob/master/crossbeam-epoch/src/guard.rs) | guard 与延迟释放；线程内 epoch 不提供进程死亡恢复 |

优先追踪具体所有权与失败路径，不照搬框架的命名或类层次。项目有更近的同类实现时，先读它。

## 借鉴 Rust 的设计

- 指出参考机制保证了什么，以及 C++ 用什么维持同一不变量：移动 owner、RAII guard、受约束构造、具名状态或现有 Result。
- Rust 的借用检查、Send/Sync、Pin 和 Drop 有各自前提。C++ 的 `const`、`shared_ptr`、`std::move` 不自动提供相同保证。
- 让额度、登记或借用保护随 owner 转移；构造和投递失败时也必须有人承担清理。跨进程回收仍由协议确认。
- trait、typestate、Builder 和 variant 只在当前状态组合确有风险时采用。普通值对象和几个清楚的函数足够时就保持简单。
- 参考测试中的失败、取消与重入场景，在本项目的真实合同下建立独立验证。相似代码不等于相同的正确性证明。
