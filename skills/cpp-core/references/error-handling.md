# 错误处理与异常安全

设计错误类型、传播错误、处理系统调用失败或决定函数的异常保证时阅读。项目已有的错误模型（`Status`、`Result`、异常、错误码）优先，不并行引入第二套。

## 选择错误模型

| 情况 | 处理方式 |
| --- | --- |
| 调用方可以合理应对的失败：文件不存在、超时、对端拒绝、输入不合法 | 返回 `Status`/`Result`（或项目使用的异常） |
| 合法的“没有结果” | `std::optional`，或项目的 not-found 约定 |
| 程序内部不变量被破坏：下标越界、状态机进入不可能的状态 | 断言并终止，附带足以定位的上下文；不继续运行在损坏的状态上 |
| 资源耗尽且无法降级 | 按项目约定终止或返回明确错误；不要静默截断数据 |

同一个函数不混用两种失败通道（既抛异常又返回错误码）。库的公开接口写清楚每种失败如何报告。

## 设计 Status / Result

- 成功路径开销要低：`ok()` 不分配内存，错误信息只在失败时构造。
- 错误包含可程序判断的代码（枚举或 `std::error_code`）和给人看的上下文，不靠解析字符串做决策。
- 返回 `Status`/`Result` 的函数标 `[[nodiscard]]`；类型本身也可以标 `[[nodiscard]]`，让所有返回它的函数自动受检。
- 传播用项目已有的宏或 C++23 `std::expected` 的 `and_then`/`transform`。宏形如：

```cpp
#define PROJECT_RETURN_IF_ERROR(expr)                  \
  do {                                                 \
    if (auto status_ = (expr); !status_.ok()) {        \
      return status_;                                  \
    }                                                  \
  } while (false)
```

- 转换错误时附加本层才知道的信息（文件名、请求 id、偏移），不重复下层已有的内容。

## 系统调用错误

- `errno` 是线程局部的，但任何后续调用都可能改写它。失败后立即读取并转换，中间不要插入日志或其他调用：

```cpp
[[nodiscard]] inline std::error_code LastSystemError() noexcept {
  return {errno, std::system_category()};
}

const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
if (fd < 0) {
  const std::error_code error = LastSystemError();   // 先保存，再记录日志
  return Status::FromSystemError(error, "open " + path.string());
}
```

- 比较时用可移植的条件：`error == std::errc::no_such_file_or_directory`，而不是比较平台相关的整数值。
- `EINTR` 和部分完成的读写需要循环处理，见 OS 接口参考。

## 异常安全保证

即使项目不使用异常，分配失败、回调失败和提前返回也会让对象停在中间状态。每个修改状态的操作都应能说明它提供哪一级保证：

| 保证 | 含义 | 典型做法 |
| --- | --- | --- |
| 不失败（nothrow） | 一定成功 | 析构、`swap`、移动操作、释放资源 |
| 强保证 | 失败时状态与调用前相同 | 先在局部构造新状态，全部成功后再用不失败的操作提交 |
| 基本保证 | 失败时不泄漏、不变量仍成立，但状态可能已改变 | 分步修改时每一步都保持不变量 |

```cpp
// 强保证：所有可能失败的工作都在提交前完成。
// PROJECT_ASSIGN_OR_RETURN 代表项目已有的“取值或返回错误”宏。
Status Index::Rebuild(std::span<const Record> records) {
  std::vector<Entry> next;
  next.reserve(records.size());
  for (const Record& record : records) {
    PROJECT_ASSIGN_OR_RETURN(Entry entry, Decode(record));   // 失败时 entries_ 未被修改
    next.push_back(std::move(entry));
  }
  entries_.swap(next);   // 不失败的提交
  return Status::Ok();
}
```

## noexcept 策略

- 析构函数默认就是 `noexcept`，不要在析构中抛出。
- 移动构造、移动赋值和 `swap` 标 `noexcept`：`std::vector` 扩容时只有 `noexcept` 的移动才会被用来代替复制。
- 可能失败的函数不要标 `noexcept`。`noexcept` 函数内抛出的异常会直接调用 `std::terminate`。
- 回调、跨 C 接口和线程入口函数是异常不能穿过的边界：在边界处捕获并转换成错误码或终止。

## 无异常环境

使用 `-fno-exceptions` 时，标准库在本该抛出的地方会终止程序（例如 `std::vector::at` 越界、分配失败）。这类项目：

- 不调用依赖异常报告失败的接口，或先检查前置条件。
- 内存分配失败通常按终止处理；确需降级时在边界使用 `new (std::nothrow)` 或自定义分配器并检查结果。
- 第三方库的异常要在包装层转换，确认它们在无异常模式下的行为。

## 断言

- 区分始终启用的检查（`CHECK`，保护在 Release 中也必须成立的不变量）和只在调试构建中启用的检查（`DCHECK`/`assert`）。
- 断言消息包含相关的值：`CHECK(offset <= size) << "offset=" << offset << " size=" << size` 一类写法（按项目宏的实际用法）。
- 不用断言校验外部输入；断言被关闭后，输入错误就会变成未定义行为。

## 重试与分类

- 区分可重试的瞬时错误（超时、连接重置、`EAGAIN`）与永久错误（参数错误、权限不足、数据损坏）。只对前者重试，并设置上限、指数退避和抖动。
- 重试必须满足幂等，或带有去重标识；不确定对端是否已执行时，不能把“未收到响应”当作“未执行”。
