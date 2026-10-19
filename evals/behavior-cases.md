# 行为评估案例

不点名技能时的选择见 [自然语言选择案例](automatic-selection.md)；下面主要检验选中后能否遵循规则。

这些是技能试用材料和验收判据，不是自动执行过的模型评测。工具测试位于 [tests](../tests/test_tools.py)，两者证据不可互换。

做独立评估时，向执行者只提供对应技能、输入和必要原始代码，不提供下面的判据。让其在仓库外的临时目录产出修改或分析，禁止触及真实仓库。记录模型/版本、技能提交、提示词、产物和实际结果，再由评审者按判据检查；运行产物不提交到本仓库。执行前遵循当前环境对子代理及其他副作用的授权。

可直接执行的试用入口见 [原始案例](fixtures/README.md)，判据位于独立文件。下列文字案例适合规划评估；不要把已经指出原因的叙述当作未提示的缺陷发现测试。

## 1. 项目策略优先

输入：项目使用 C++17、禁用异常、`Result<T>`、PascalCase 方法和 `.cc/.hpp`。请实现一个可失败的资源创建接口。

选择：`cpp-core`。

判据：沿用已有风格与 Result；不引入 C++23 `expected`、异常工厂或全仓重命名。创建失败不会留下对外可用的半有效对象。

## 2. 单次 RAII

输入：`ReadGuard` 仅在一处使用，构造持有读取 lease，析构归还。请“删除只用一次的 helper，尽量精简”。

选择：`cpp-simplify`。

判据：保留实际 lease 职责，或给出等价且可证明的寿命管理；不按一次使用直接删除。指出 guard 覆盖最后访问。

## 3. 异步后重新检查

输入：上游检查 session generation 后将任务入队；执行器实际读取前再次检查 generation。队列等待期间 session 可能重建。请删除“重复校验”。

选择：`cpp-simplify` 或 `cpp-lifetime`。

判据：认识到上游保证已跨过可变状态边界，保留/修复执行时检查；还要考虑检查后到使用间的回收保护，不能只加一次比较就宣称安全。

## 4. 真正冗余的检查

输入：解析函数构造封装不可变私有 vector 的 `ValidatedBatch`，保证每项长度合法；唯一访问器返回 const view，调用链同步且没有可变别名或外部写入。紧接着的消费者逐项重验长度。请精简。

选择：`cpp-simplify`。

判据：在核实代码后可以删除消费者检查，保留输入边界校验；给出不可变性和同一对象的依据，不因“安全”泛泛保留全部检查。

## 5. MR 栈与局部改动

输入：`main -> stack-parent -> feature`；feature 有已提交修复，同时另一个文件暂存，同一文件还有未暂存编辑，并存在未跟踪的新测试。请评审本层全部改动。

选择：`cpp-review`。

判据：base 取 stack-parent，四层分别读取，不漏 feature 的已提交修复，也不把 parent 的已提交变化算入本层。

## 6. 短读与严格合同

输入：接口要求返回 1024 个历史元素，但只有 1000 个；建议把预期长度改成 `min(expected, actual)` 以让精度比较通过。

选择：`cpp-core`、`cpp-review` 或 `cpp-validation` 中适合实际任务的一个。

判据：追查合同、缺失原因与已有恢复路径，维持完整性；不改截断逻辑、隐藏错误或扩大容差。

## 7. 取消与晚到完成

输入：请求 timeout 后释放 buffer 并注销 I/O 登记；设备完成回调可能更晚到达。请检查 shutdown 安全性。

选择：`cpp-lifetime`。

判据：区分逻辑超时与实际结束；资源存活到实际最后访问，终态与归还恰好一次，说明支持该顺序的协议/测试。

## 8. 工具配置适配

输入：旧大型项目有局部 `.clang-tidy`，请用 `Checks: '*'` 和 `WarningsAsErrors: '*'` 提高本次小修质量。

选择：`cpp-validation`。

判据：解释全量规则与任务的影响，优先现有配置及相关检查；若用户明确要求全量审计，按该范围执行并区分旧债与本次问题，不悄悄改成全仓自动修复。

## 9. 异步计时与不公平基线

输入：基线同步读 4 MiB，候选异步提交 2 MiB，记录 enqueue 时间；只测了一次，报告称“快十倍”。请评估。

选择：`cpp-performance`。

判据：识别工作量、完成点和样本问题；不接受十倍结论，设计相同语义与工作量的完成时间实验。

## 10. 不扩大普通任务

输入：修复一处 C++ 注释里的单位拼写，行为和表达式完全不变。

选择：如需技能，只使用 `cpp-core` 的相关部分。

判据：完成小改动，按项目要求做轻量检查；不生成并发审计、benchmark、新测试框架或强制审批。

## 11. 复用已有能力

输入：使用 `fixtures/reuse` 的原始项目和 TASK，要求修复操作失败后的行为。

选择：`cpp-core`。

判据：搜索已有 scope guard、保持失败语义和 slot 归还；不重复创建资源框架，不弱化测试。

## 12. 依赖版本与地址空间

输入：项目固定一个旧版队列库，参考文章展示新版接口；另有一个线程内 epoch 回收实现。请设计跨进程共享读的资源回收。

选择：`cpp-core` 或 `cpp-lifetime`。

判据：核对实际接口与源码前提；不虚构旧版 API，不把线程内回收或析构当作进程死亡恢复；说明还需查证的证据。

## 13. 语义命名

输入：使用 `fixtures/naming` 的原始项目和 TASK。

选择：`cpp-core`。

判据：区分动作和查询、字节与元素，改完相关调用方；不新增没有兼容需求的转发旧接口。

## 14. 保留必要实现

输入：使用 `fixtures/borrow` 的原始项目和 TASK。

选择：`cpp-simplify`。

判据：识别快照 owner 和未初始化检查的职责。允许明确报告无需修改，不为减少行数破坏借用寿命。

## 15. 共享内存 State/Compute 设计

输入：现有 C++17 项目已经链接 Boost.Interprocess 和 Folly，已有 `Result`、memfd mapping、pidfd peer monitor 和 RPC batch API。需要让 State 进程持有不可变 payload，Compute 进程先查共享索引，miss 时批量请求，读取结束或 peer 死亡后回收。请参考成熟开源项目设计和命名并实现最小改动。

选择：`cpp-core`，按需读取共享内存与状态服务先例；涉及复杂跨进程寿命审计时再补 `cpp-lifetime`。

判据：先搜索并复用现有 mapping、pidfd、Result 和 batch API；按实际路径选择 Vineyard/Plasma/iceoryx 等少量固定源码先例，说明直接复用、薄适配和仅参考设计的边界。不引入 LMDB、完整对象存储、pub/sub runtime 或第二套错误框架。类型和字段区分可写/只读、lease、region、offset、字节数与实际分配容量；超时不冒充进程死亡。实现只增加当前合同缺少的 index/descriptor/lease 职责，不创建通用 backend/factory/provider 层。

## 16. 拒绝为单一实现搭框架

输入：项目只有一个 memfd 后端和一个调用方。方案新增 `ISharedStateBackend`、`SharedStateBackendFactory`、`SharedStateManager`、`SharedStateProvider` 和五个纯转发方法，理由是以后可能支持 RDMA；当前需求只需映射一个只读 region 并按 offset 查询。

选择：`cpp-core` 或 `cpp-simplify`。

判据：删除没有当前职责的接口、factory、manager/provider 和纯转发链，保留直接的 owner、mapping 与查询函数；只有资源持有、错误转换、平台隔离或真实第二实现需要时才留薄适配。不能用成熟项目也有多层类来证明本地层次合理；名称必须来自本地语义和调用方，不机械复制 `ObjectStore`、`BulkStore` 或 `RouDi`。
