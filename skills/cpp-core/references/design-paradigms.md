# 设计范式

在设计新类型、模块边界或状态机时按需阅读。每个范式都写了适用条件和不适用的情况；当前需求不满足适用条件时，用更直接的写法。项目已有的同类模式优先。

## 值语义与规则类型

数据描述和小型对象优先做成可复制、可比较、无隐藏共享的值。C++20 起用默认比较减少样板：

```cpp
struct BlockId {
  std::uint64_t file = 0;
  std::uint32_t offset = 0;

  friend bool operator==(const BlockId&, const BlockId&) = default;
  friend auto operator<=>(const BlockId&, const BlockId&) = default;
};
```

字段彼此独立时用 `struct` 加公开字段；字段之间有必须共同成立的约束时用 `class`，只暴露维持约束的操作。

## 构造即有效

对象构造完成就满足全部不变量，不暴露“已构造但未初始化”的状态。可能失败的创建放进返回 `Result` 的静态工厂，构造函数设为私有：

```cpp
class Segment {
 public:
  [[nodiscard]] static Result<Segment> Open(const std::filesystem::path& path);

  [[nodiscard]] std::span<const std::byte> Bytes() const noexcept;

 private:
  explicit Segment(MappedRegion region) : region_(std::move(region)) {}

  MappedRegion region_;
};
```

不适用：协议本身要求分阶段（例如先注册再激活）。这时用具名状态表示阶段，并限制每个阶段可调用的操作。

## RAII owner

文件、映射、锁、注册句柄、额度都由一个 owner 负责释放。优先 `std::unique_ptr` + 删除器 struct；需要额外状态或更丰富接口时手写 owner，并同时决定复制、移动、析构与 moved-from 状态。释放可能失败且调用方需要知道时，提供显式 `Close()` 返回错误，析构函数只做不抛出的兜底释放。

回滚类操作用作用域 guard（项目已有的 `ScopeExit`、Folly `ScopeGuard` 或 `absl::Cleanup`），不在每个提前返回分支重复清理代码。

## 选项结构与指定初始化

参数多于三四个、或多个同类型参数容易传错时，用选项结构，C++20 用指定初始化：

```cpp
struct CacheOptions {
  std::size_t capacity_bytes = 64 << 20;
  std::chrono::milliseconds ttl{0};
  bool record_stats = false;
};

Cache cache(CacheOptions{.capacity_bytes = 1 << 30, .ttl = std::chrono::seconds(30)});
```

字段带默认值并写明单位。只有构造过程需要多步校验或依赖顺序时才用 Builder；普通配置不需要 Builder。

## 封闭集合用 variant，开放扩展用虚函数

状态或消息种类在本模块内固定时用 `std::variant`，编译器能检查是否处理了所有情况：

```cpp
template <class... Ts>
struct Overloaded : Ts... {
  using Ts::operator()...;
};
template <class... Ts>
Overloaded(Ts...) -> Overloaded<Ts...>;  // C++17 需要；C++20 起可省略

struct Idle {};
struct Loading { RequestId request; };
struct Ready { Lease lease; };
using SlotState = std::variant<Idle, Loading, Ready>;

std::string_view Describe(const SlotState& state) {
  return std::visit(Overloaded{
      [](const Idle&) { return std::string_view("idle"); },
      [](const Loading&) { return std::string_view("loading"); },
      [](const Ready&) { return std::string_view("ready"); },
  }, state);
}
```

需要由其他模块或插件新增实现时才用虚函数接口。接口保持窄小，基类析构函数 `virtual` 或 `protected`，实现类标 `final`。只有一个实现且没有测试替身需求的接口直接删掉。

## 依赖注入，不用单例

依赖通过构造函数传入：被借用的依赖传引用或指针并写清寿命，被拥有的依赖传 `std::unique_ptr`。时钟、文件系统、网络这类需要在测试中替换的依赖才抽象成接口。不写全局单例和可变全局状态；进程级唯一资源由 `main` 或服务入口创建后向下传递。

## 回调与生命周期

回调捕获 `this` 或引用之前，确认回调一定在对象销毁前执行或被取消。做不到时使用取消句柄（析构时注销）、`std::weak_ptr` 检查，或把回调所需状态按值移入闭包。只移动的回调在 C++23 用 `std::move_only_function`，已有 Abseil 时用 `absl::AnyInvocable`。热路径上避免 `std::function` 的分配与间接调用，必要时用模板参数接收可调用对象。

## 不可变快照

读多写少的配置或索引，用 `std::shared_ptr<const T>` 发布不可变快照，写者构造新快照后整体替换。C++20 的 `std::atomic<std::shared_ptr<const T>>` 并非所有标准库都实现：libstdc++ 从 GCC 12 起支持，libc++ 截至 LLVM 22 仍未提供，用 `__cpp_lib_atomic_shared_ptr` 判断。不可用时用互斥锁保护指针的读取与替换，临界区内只复制或交换 `shared_ptr`。读者持有快照期间看到的数据不会被修改；快照本身不提供跨进程或设备 DMA 的寿命保证。

## Pimpl 与编译防火墙

公开头文件需要稳定 ABI，或者需要把重依赖（CUDA、平台头文件、大型第三方库）挡在头文件之外时，用 Pimpl：

```cpp
// engine.h
class Engine {
 public:
  explicit Engine(EngineOptions options);
  ~Engine();                          // 在 .cc 中定义，那里 Impl 是完整类型
  Engine(Engine&&) noexcept;
  Engine& operator=(Engine&&) noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
```

不适用：内部类型和热路径对象。Pimpl 增加一次分配和一次间接访问。

## 强类型

只有单位或含义容易混淆、并且已经出过错或代价高时才包装：例如字节数与元素数、逻辑块号与物理块号。时长直接用 `std::chrono`。不要给每个整数都套一层类型。

## 命名空间与可见性

- 代码放在 `project::module` 命名空间；实现细节放 `detail` 或 `internal`，只在本编译单元使用的函数和常量放匿名命名空间。
- 公开头文件只声明调用方需要的类型和函数；私有辅助类型放在实现文件或私有头文件中。
- 共享库导出符号时，默认隐藏、显式导出（CMake 的 `CXX_VISIBILITY_PRESET hidden` 加生成的导出宏，Blade 用 `export_map` 或 `cc_plugin`）。

## 错误分层

底层返回具体错误（errno、设备状态），中间层转换成项目的 `Status` 并附加上下文，边界层（RPC、CLI、Python 绑定）再转换成对外格式。每一层只在有新信息时添加上下文，同一错误只记录一次日志。

## 何时停止抽象

新类型、接口或模板都要能回答：它维持了什么不变量、拥有什么资源、隔离了什么依赖，或者被几个实际调用方复用。答不出来就直接写函数。不要预先为“以后可能的需求”设计插件点、策略模板或配置开关。
