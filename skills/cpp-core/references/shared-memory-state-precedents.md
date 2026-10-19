# 共享内存与状态服务先例

用于计算/存储进程分离、共享内存数据面、不可变对象、快照读取、lease 和进程死亡回收。先写清实际场景，再选两三个最接近的先例；这些项目默认是设计参考，不是待引入的依赖。

资料核对日期：2026-10-19。下列结论来自固定提交中的架构文档、接口与实现，不代表构建或性能验证。

## 从场景进入源码

| 当前问题 | 先看 | 重点文件与符号 | 只借鉴什么 |
| --- | --- | --- | --- |
| 本地 daemon 持有数据，计算进程通过 mmap 读不可变对象 | [Vineyard `0cbaada`](https://github.com/v6d-io/v6d/tree/0cbaada9db11d0268aa166b91cb7503bab0ccf86) | [`architecture.rst`](https://github.com/v6d-io/v6d/blob/0cbaada9db11d0268aa166b91cb7503bab0ccf86/docs/notes/architecture.rst)、[`client.h`](https://github.com/v6d-io/v6d/blob/0cbaada9db11d0268aa166b91cb7503bab0ccf86/src/client/client.h)、[`blob.h`](https://github.com/v6d-io/v6d/blob/0cbaada9db11d0268aa166b91cb7503bab0ccf86/src/client/ds/blob.h)；`IPCClient` / `RPCClient`、`SharedMemoryManager` / `MmapEntry`、`BlobWriter` / `Blob` | 控制面传元数据和 fd，数据面 mmap；写入对象 seal 后只读；本地 IPC 与远程 RPC 明确分开 |
| 需要明确 create/seal/release/delete、引用和线协议字段 | [Ray Plasma `6f01d61`](https://github.com/ray-project/ray/tree/6f01d617120885918b783086eedf712ebdb5f441) | [`object_lifecycle_manager.h`](https://github.com/ray-project/ray/blob/6f01d617120885918b783086eedf712ebdb5f441/src/ray/object_manager/plasma/object_lifecycle_manager.h)、[`common.h`](https://github.com/ray-project/ray/blob/6f01d617120885918b783086eedf712ebdb5f441/src/ray/object_manager/plasma/common.h)、[`plasma.fbs`](https://github.com/ray-project/ray/blob/6f01d617120885918b783086eedf712ebdb5f441/src/ray/object_manager/plasma/plasma.fbs) | 生命周期动词、move-only `Allocation`、服务内对象与 wire descriptor 分离、偏移和字节数的精确命名 |
| 多读者要固定一致视图，需处理陈旧 reader 登记 | [LMDB `253ba52`](https://github.com/LMDB/lmdb/tree/253ba5219172531b719bc14fee6b4aa1a2a5c4a5) | [`intro.doc`](https://github.com/LMDB/lmdb/blob/253ba5219172531b719bc14fee6b4aa1a2a5c4a5/libraries/liblmdb/intro.doc)、[`lmdb.h`](https://github.com/LMDB/lmdb/blob/253ba5219172531b719bc14fee6b4aa1a2a5c4a5/libraries/liblmdb/lmdb.h)、[`mdb.c`](https://github.com/LMDB/lmdb/blob/253ba5219172531b719bc14fee6b4aa1a2a5c4a5/libraries/liblmdb/mdb.c)；`mdb_txn_begin/reset/renew`、`mdb_reader_check` | 读事务即快照、reader slot 的占用期、句柄复用与逻辑读取期分开、死亡 reader 检查 |
| 零拷贝消息要 loan/publish/take/release，并在进程崩溃后收回借用 | [iceoryx `9f9fb0d`](https://github.com/eclipse-iceoryx/iceoryx/tree/9f9fb0d359f1805cdd38006c8aba6af6dbc2209e) | [`used_chunk_list.hpp`](https://github.com/eclipse-iceoryx/iceoryx/blob/9f9fb0d359f1805cdd38006c8aba6af6dbc2209e/iceoryx_posh/include/iceoryx_posh/internal/popo/used_chunk_list.hpp)、[`publisher_impl.inl`](https://github.com/eclipse-iceoryx/iceoryx/blob/9f9fb0d359f1805cdd38006c8aba6af6dbc2209e/iceoryx_posh/include/iceoryx_posh/internal/popo/publisher_impl.inl)、[`subscriber_impl.inl`](https://github.com/eclipse-iceoryx/iceoryx/blob/9f9fb0d359f1805cdd38006c8aba6af6dbc2209e/iceoryx_posh/include/iceoryx_posh/internal/popo/subscriber_impl.inl)、[`process_manager.cpp`](https://github.com/eclipse-iceoryx/iceoryx/blob/9f9fb0d359f1805cdd38006c8aba6af6dbc2209e/iceoryx_posh/source/roudi/process_manager.cpp) | 借出、发布、接收和归还的动作边界；崩溃可审计的固定容量借用表；确认进程死亡后再 cleanup |
| 想借 Rust 所有权表达和阶段命名，但实现仍是 C++ | [iceoryx2 `9f1ddda`](https://github.com/eclipse-iceoryx/iceoryx2/tree/9f1ddda76a51bf836c6cffe9cefe0006d0e74fae) | [`sample_mut.rs`](https://github.com/eclipse-iceoryx/iceoryx2/blob/9f1ddda76a51bf836c6cffe9cefe0006d0e74fae/iceoryx2/src/sample_mut.rs)、[`sample.rs`](https://github.com/eclipse-iceoryx/iceoryx2/blob/9f1ddda76a51bf836c6cffe9cefe0006d0e74fae/iceoryx2/src/sample.rs)、[`pending_response.rs`](https://github.com/eclipse-iceoryx/iceoryx2/blob/9f1ddda76a51bf836c6cffe9cefe0006d0e74fae/iceoryx2/src/pending_response.rs)、[`active_request.rs`](https://github.com/eclipse-iceoryx/iceoryx2/blob/9f1ddda76a51bf836c6cffe9cefe0006d0e74fae/iceoryx2/src/active_request.rs)、[`request_response.rs`](https://github.com/eclipse-iceoryx/iceoryx2/blob/9f1ddda76a51bf836c6cffe9cefe0006d0e74fae/iceoryx2/src/service/builder/request_response.rs) | 类型名表达可写/只读和 pending/active 阶段；Drop 对应 C++ RAII；不同资源限制使用不同 capacity 名称 |
| 只缺跨地址空间的相对寻址或映射设施 | 已链接的 [Boost.Interprocess](https://www.boost.org/doc/libs/latest/doc/html/interprocess.html) | `managed_shared_memory`、[`offset_ptr`](https://www.boost.org/doc/libs/latest/doc/html/interprocess/offset_ptr.html) | 能直接满足合同就调用库；generation、协议版本、lease 和死亡回收仍由本项目负责 |

不要因为同属“共享内存”就把所有项目都读一遍。不可变对象服务通常先对照 Vineyard 和 Plasma；消息借用与崩溃回收先对照 iceoryx；仅讨论快照 pin 时再看 LMDB。

## 源码中可迁移的设计

### Vineyard：控制面与数据面分开

- daemon 端分为共享内存、metadata manager 和 IPC/RPC server。`IPCClient` 通过 Unix socket 接收 fd 并 mmap；`RPCClient` 用于远程访问，不提供同样的进程间映射语义。
- `BlobWriter` 表示 seal 前可写对象，`Blob` 表示 seal 后读取对象。`CreateBlob`、`Seal`、`Abort`、`Release` 和 `Delete` 的名称分别表达分配、发布、放弃创建、放下使用权和删除意图。
- `MmapEntry` 持有 fd、映射长度以及只读/可写地址，`SharedMemoryManager` 维护映射表。可以参考职责边界，不要为了一个固定数据类型照搬 builder/resolver/registry 扩展体系。
- Vineyard 明确把 sealed 对象设为不可变；如果本地对象频繁原地更新，这个先例不成立，不能只复制类名。

### Ray Plasma：对象生命周期和 wire descriptor

- `ObjectLifecycleManager` 负责 created/sealed 状态、引用计数、删除等待和 eviction；`ObjectStore` 保存对象，allocator 只负责分配。只有本地设计确有这些独立职责时才拆成对应对象。
- `Allocation` 是 move-only owner，字段区分 `size_`、`offset_` 和 `mmap_size_`。客户端的 `ObjectBuffer` 持有 data/metadata buffer；wire 层使用 `segment_index`、`unique_fd_id`、`data_offset`、`data_size`、`metadata_offset`、`allocated_size`、`mmap_size`。
- 这些名称说明“哪个 region、相对何处、请求大小还是实际分配大小”。本地协议也应把单位和基准写进名称或类型，不能只叫 `index`、`offset`、`size`。
- 上游接口本身留有“返回裸指针应改 RAII”的 TODO。参考项目不是正确性豁免；借机制时仍按本项目所有权规则修正。

### LMDB：快照与 reader 登记

- `MDB_txn` 同时表达读取快照和 reader slot 的占用期。`mdb_txn_reset` 释放旧快照保留的版本，`mdb_txn_renew` 让同一 handle 开始新的读取期；handle 复用不等于仍在同一快照。
- `MDB_NOTLS` 会改变 reader slot 绑定在线程还是 transaction 上，说明并发和跨线程语义必须进入接口合同，不能藏在实现细节中。
- `mdb_reader_check` 用于清理陈旧 reader slot。它适合帮助设计 snapshot/reader registry，不提供通用 State service、payload lease 或任意异步任务的生命周期方案。
- LMDB 的 C API 名称服务于稳定 ABI。C++ 项目应借用 `ReadSnapshot`、`Reset`、`Renew` 等语义，不复制 `MDB_` 风格或把 transaction 强套到普通 buffer 上。

### iceoryx：借用路径与崩溃回收

- publisher `loan` 可写 sample，`publish` 先移交 sample 对 chunk 的所有权再发送；subscriber `take` 返回带 deleter 的只读 sample，析构时 `releaseChunk`。C++ 中可用一个 move-only loan/lease 表达同一保证。
- `UsedChunkList<Capacity>` 用固定数组记录应用持有的 chunk。其注释明确拒绝可能在进程崩溃中损坏的 vector/list，并限制单次写入大小以避免 torn write；这是真实崩溃模型产生的结构，不是通用容器建议。
- `ProcessManager` 通过 heartbeat 监控并清理进程资源。若本地已有 pidfd 或等价的内核死亡确认，应保留更强的确认机制，不退化成超时即回收。
- 若实际需求是一次批量 request/response，不应为了复用命名而引入完整 pub/sub、port discovery 或中央守护进程框架。

### iceoryx2：让名称表达状态和所有权

- `SampleMut` 是尚未发送的可写 loan；发送后接收方得到只读 `Sample`，两者的 Drop 分别承担未发送归还和读取结束归还。
- `PendingResponse` 表达客户端仍等待响应，`ActiveRequest` 表达服务端仍可响应的请求。只有这些状态确实限制可用操作时才拆类型；若一个枚举和两个函数足够，不做 typestate 框架。
- `max_loaned_requests`、`max_active_requests_per_client`、`max_response_buffer_size`、`max_borrowed_responses_per_pending_response` 刻意区分不同额度。不要把它们合成含混的 `max_count`，也不要为每个整数机械创建包装类。

## 复用和停止流程

1. 先写一条实际路径，例如“compute 查询共享索引；命中后用 region-relative offset 读取；miss 批量请求 state；lease 或 peer death 后回收”。同时列出 writer、reader、最后一次访问和死亡确认者。
2. 在仓库中按职责、动词、错误文本和调用方搜索，并从构建文件确认标准库及 Boost/Folly/Arrow 等实际链接版本。找到合适 owner、guard、mapping 或 pidfd 组件就直接复用。
3. 只选失败模型和所有权最接近的两三个先例，读取上表所列实现、调用方和测试。提取名词、状态转移、单位/容量、owner/borrow 和崩溃恢复，不按项目知名度选型。
4. 给每项能力标记一种结论：直接调用已有符号；写承担语义转换或资源持有的薄适配；只借设计；确有缺口才自行实现。不要用一个“统一抽象”同时掩盖四种结论。
5. 选择最小实现：一个现有库调用、一个 move-only lease 和几个直接函数能满足当前合同，就不要再加 backend interface、factory、manager、provider、builder 或兼容层。
6. 当本地能力和一个源码先例已经覆盖所有权、失败和关闭路径时停止研究并实现。只有新证据表明前提不匹配时才扩大搜索。

需要留下决策记录时，用四行即可：实际场景；本地已复用的符号/版本；读过的上游 commit、文件和机制；未采用的框架层及原因。不要生成与代码脱节的通用架构报告。
