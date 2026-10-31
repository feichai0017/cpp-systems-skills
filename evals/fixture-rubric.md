# 原始代码案例评审判据

本文件仅供评审者使用。执行者不能读取本文件或之前的评估结论。

## reuse

- 行为：成功、操作失败后均归还已取得的 slot；没有取得 slot 的拒绝路径不能释放他人的占用。
- 复用：先发现并评估项目已有 `ScopeExit`。采用它是符合技能的最小改动；若使用直接控制流，须说明为什么在当前固定路径下更合适。新建另一套 ScopeExit/Lease 框架不符合目标。
- 验证：原失败场景修复后通过，不能删除或弱化行为检查。

## borrow

- 无需修改是合格结果。`ReadWindow` 持有旧快照，`Store::Replace` 不应使已有 view 失效。
- `Read` 的空指针检查区分尚未初始化与合法空字符串，不能当作冗余校验删除。
- 不能用不持有 owner 的 `string_view` 替代 ReadWindow，不能为消除 shared_ptr 引入无关池或锁。
- 结论应定位 owner 与最后访问，不只写“智能指针安全”。

## naming

- 区分返回模式的查询与实际量化动作，以及 stored value 的字节数。
- 修改全部调用方并保持值与返回类型不变；无需旧名兼容转发层，因为输入明确给出全部调用方且允许修改。
- 不要求某个唯一拼写，但应符合项目命名规则且无歧义。验证通过不替代语义判断。

## owner

- 行为：成功与非法头部两条路径都释放区域，`live_regions` 检查保留且通过；区域打开失败时不调用 `CloseRegion`。
- 所有权：用 RAII 绑定释放。`std::unique_ptr<c_api::Region, 删除器 struct>` 是最直接的解法；函数指针删除器（`decltype(&c_api::CloseRegion)`）也能修复泄漏，但不符合技能对删除器 struct 的要求，记为部分满足；手写 owner 时须删除复制、移动操作 `noexcept`、moved-from 状态不会重复释放。只在失败分支补一行 `CloseRegion` 修复了泄漏，但没有建立所有权，不符合技能目标。
- 现代写法：按项目约定改为返回 `std::optional<Header>`，去掉输出参数；不写裸 `new`/`delete`；不使用超出 C++17 的设施（例如 `std::span`）；不修改 `c_region.h`。
- 范围：不新建通用资源框架，不引入异常。

## views

- 行为：三个校验和保持原值；`ParseLimit` 对 `"42"` 成功，对空、非数字、`"42x"`、非正数报告 `kInvalidArgument`，对超出 `int` 的输入报告 `kOutOfRange`。
- 现代写法：`Checksum` 接收 `std::span<const std::byte>` 或 `std::span<const std::uint8_t>`，调用方不再复制（`std::as_bytes`、`subspan` 或字符串的字节视图）；`ParseLimit` 接收 `std::string_view`，用 `std::from_chars`，返回项目的 `Result<int>`；返回值标 `[[nodiscard]]` 可加分但不是必需。
- 约定：沿用 `result.hpp`，不引入 `std::expected`（C++23）或新的错误类型；去掉 `atoi` 和输出参数。
- 验证：`check.cc` 覆盖新的错误区分，不删除原有校验和断言。

## standard-gate

- 标准：以 `-std=c++14` 编译通过，不使用 `std::optional`、`std::string_view`、结构化绑定、`if` 初始化语句、`[[nodiscard]]` 等 C++17 设施，也不建议升级标准。GCC 14 在 C++14 下仍接受 `[[nodiscard]]`，需人工检查或用 clang 编译确认。
- 约定：查找接口返回 `const Entry*`，不存在时为 `nullptr`，与 `FindConfig` 一致；函数为 `const`；用 `map::find`，不用 `operator[]` 意外插入。
- 现代写法仍然适用于 C++14：`auto`、range-for、`std::make_unique`（如需要）、`nullptr`，不写裸 `new`。
- 验证：`check.cc` 覆盖存在与不存在两种情况。

## short-io

- 行为：循环直到写完整条记录；`EINTR` 时重试；其他错误立即返回对应的 `std::error_code`；写入函数返回 0 时报告错误而不是无限循环。
- 写法：用 `span::subspan` 推进剩余数据，不复制记录；保留 `std::error_code` 约定，不引入异常或新的错误类型；返回值可以标 `[[nodiscard]]`。
- 验证：保留原有两个断言，可补充返回 0、多次中断的情况；不修改模拟写函数来让检查通过。

## 记录方法

在仓库外记录每次执行的模型/宿主、skill 与输入快照、原始提示、修改及命令结果，不提交运行报告或产物。分别标注行为、复用、保持不变量、范围控制和证据是否满足。

同一模型的一次成功只能算一次 smoke。规则修改后使用新的同类输入复测，不把已泄露判据的重复运行计作独立评估。
