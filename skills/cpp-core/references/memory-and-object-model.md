# 内存与对象模型

处理分配策略、对齐、原始字节与对象之间的转换、整数与位运算，或者排查“看起来正确却偶尔出错”的内存问题时阅读。

## 分配

- 热路径上避免每次操作都分配：复用缓冲区、按已知大小 `reserve`、使用对象池或 arena。先用 profiler 确认分配确实是成本。
- `std::pmr`（C++17）可以让容器从指定的内存资源分配，例如按请求的 arena：

```cpp
std::array<std::byte, 64 * 1024> stack_buffer;
std::pmr::monotonic_buffer_resource arena(stack_buffer.data(), stack_buffer.size());
std::pmr::vector<std::pmr::string> tokens(&arena);   // 字符串也从 arena 分配
```

  内存资源必须比所有使用它的容器活得久；`monotonic_buffer_resource` 只在自身销毁时整体释放，不适合长期增长的容器。
- 分配后马上会被覆盖的大缓冲区，用 `std::make_unique_for_overwrite<T[]>(n)`（C++20）避免无用的清零。
- 全进程替换分配器（jemalloc、mimalloc、tcmalloc）的影响见基础库选型参考。

## 对齐与缓存行

- 需要特定对齐的类型用 `alignas`；C++17 起 `new` 会遵守超过默认对齐的类型要求。原始缓冲区用 `std::aligned_alloc`（大小必须是对齐值的倍数）或 `operator new(size, std::align_val_t{alignment})`，并用对应方式释放。
- 被不同线程频繁写入的数据放在不同的缓存行，避免伪共享：

```cpp
#if defined(__cpp_lib_hardware_interference_size)
inline constexpr std::size_t kCacheLine = std::hardware_destructive_interference_size;
#else
inline constexpr std::size_t kCacheLine = 64;
#endif

struct alignas(kCacheLine) PerCoreCounter {
  std::atomic<std::uint64_t> value{0};
};
```

  `std::hardware_destructive_interference_size` 并非所有标准库都提供，而且可能随编译选项变化，不要把它用在跨编译单元或跨进程共享的布局里。
- 访问未对齐地址在部分平台上是未定义行为或很慢。从字节缓冲区读取数值用 `std::memcpy`，而不是把指针强转成 `std::uint32_t*`。

## 原始字节与对象

- 只有 `char`、`unsigned char` 和 `std::byte` 可以访问任意对象的字节。把 `float*` 当 `std::uint32_t*` 读取违反严格别名规则，是未定义行为。类型双关用 `std::bit_cast`（C++20）或 `std::memcpy`：

```cpp
static_assert(std::is_trivially_copyable_v<RecordHeader>);
static_assert(sizeof(RecordHeader) == 16);

[[nodiscard]] Result<RecordHeader> ReadHeader(std::span<const std::byte> bytes) {
  if (bytes.size() < sizeof(RecordHeader)) return Status::InvalidArgument("short header");
  RecordHeader header;
  std::memcpy(&header, bytes.data(), sizeof(header));
  return header;
}

const auto bits = std::bit_cast<std::uint32_t>(1.0f);
```

- 这种直接拷贝只适用于进程内或同一构建产物之间；写到磁盘或网络的格式应按字段编码（见存储与网络参考）。
- `reinterpret_cast` 得到的指针不会凭空创建对象。C++20 起，`malloc`/`memcpy` 等操作会为隐式生存期类型（标量、平凡类型的聚合）隐式创建对象；C++23 的 `std::start_lifetime_as` 用于显式表达，但标准库支持很少。非平凡类型必须用 placement new 构造并显式析构。
- `std::launder` 只在极少数情况下需要（在同一存储上重新构造含 `const` 成员或引用成员的对象后访问）。遇到需要它的设计时，先考虑换一种写法。

## 整数与溢出

- 有符号整数溢出是未定义行为；无符号整数溢出会回绕，但在长度计算中同样是缺陷。
- 由外部输入计算大小或偏移时，先检查再运算：

```cpp
[[nodiscard]] inline std::optional<std::size_t> CheckedMul(std::size_t a, std::size_t b) {
  std::size_t result = 0;
  if (__builtin_mul_overflow(a, b, &result)) return std::nullopt;   // GCC 与 Clang
  return result;
}

// 不用 offset + length > size，它本身可能溢出
[[nodiscard]] inline bool RangeFits(std::size_t offset, std::size_t length, std::size_t size) {
  return offset <= size && length <= size - offset;
}
```

- 移位量必须小于类型位宽；对负数左移在 C++20 之前是未定义行为。
- 位运算用 `<bit>`（C++20）：`std::popcount`、`std::countl_zero`、`std::bit_ceil`、`std::has_single_bit`、`std::rotl`。字节序判断用 `std::endian`（C++20），转换用 `std::byteswap`（C++23）。
- 比较有符号与无符号值用 `std::cmp_less` 等（C++20），或先统一类型。

## 容器与迭代器失效

- `std::vector` 扩容会使所有指针、引用和迭代器失效；`std::deque` 在首尾插入会使迭代器失效但不使元素引用失效；节点型容器（`std::map`、`std::list`、`std::unordered_map` 的元素）插入不会使元素引用失效，但 `unordered_map` 的 rehash 会使迭代器失效。
- 保存元素地址的代码，要么使用地址稳定的容器（或 `std::unique_ptr` 元素），要么在每次修改后重新获取。
- 遍历时修改容器用 C++20 的 `std::erase_if`，或使用 `erase` 返回的新迭代器。

## 临时对象的寿命

- 从临时对象得到的 `string_view`、`span`、引用和迭代器在完整表达式结束时失效：`std::string_view name = GetName();` 在 `GetName` 返回 `std::string` 时是悬垂引用。
- 范围 for 循环中，C++23 之前，`for (auto& x : MakeObject().items())` 里 `MakeObject()` 返回的临时对象在循环开始前就已销毁；C++23 起才延长其寿命。不依赖这一点，先把对象存进局部变量。
- 函数返回成员的引用时，确认调用方不会在对象销毁后继续使用。
