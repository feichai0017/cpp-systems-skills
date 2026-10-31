# 现代 C++ 写法

先确定项目实际使用的标准、编译器和标准库，再在这个范围内用足它已允许的设施。不升级标准，也不写低于该标准的旧式代码。项目已有等价类型（`Status`、`Result`、`Span`、`StringPiece`、日志宏等）时用项目类型。

确认方式：CMake 的 `target_compile_features` / `CMAKE_CXX_STANDARD` / presets，Blade 的 `BLADE_ROOT` 中 `cc_config(cxxflags=[...])`，或实际编译命令里的 `-std=`。库设施是否可用以特性测试宏（`<version>` 中的 `__cpp_lib_*`）和 [cppreference 编译器支持表](https://en.cppreference.com/w/cpp/compiler_support) 为准，不凭记忆假设。

没有既有约束的新项目以 C++20 为基线；C++23 库设施在目标工具链确认支持后使用。

## 按标准选择设施

| 需求 | C++17 | C++20 | C++23 | 旧标准且已引入依赖时 |
| --- | --- | --- | --- | --- |
| 可失败的返回值 | 项目 `Status`/`Result` | 同左 | `std::expected` | `tl::expected`、`absl::StatusOr` |
| 合法缺席 | `std::optional` | 同左 | 同左 + monadic 操作 | — |
| 只读连续序列参数 | 项目 span 或 `(ptr, size)` | `std::span<const T>` | 同左 | `absl::Span`、`gsl::span` |
| 只读字符串参数 | `std::string_view` | 同左 | 同左 | `absl::string_view` |
| 数值与文本转换 | `std::from_chars`/`to_chars` | 同左 | 同左 | — |
| 格式化 | `fmt` | `std::format` | `std::print` | `fmt` |
| 封闭的状态/消息集合 | `std::variant` + `std::visit` | 同左 | 同左 | — |
| 模板约束 | `if constexpr`、`static_assert` | concepts、`requires` | 同左 | — |
| 范围算法 | `<algorithm>` | `std::ranges`、views | `std::ranges::to` | range-v3 |
| 可取消线程 | `std::thread` + 停止标志 | `std::jthread` + `std::stop_token` | 同左 | — |
| 计数等待 | `condition_variable` | `std::latch`、`std::barrier`、`atomic::wait` | 同左 | — |
| 类型双关/位操作 | `std::memcpy` | `std::bit_cast`、`<bit>` | `std::byteswap` | — |
| 枚举转整数 | `static_cast<std::underlying_type_t<E>>` | 同左 | `std::to_underlying` | — |
| 具名字段初始化 | 构造函数 | 指定初始化 `{.field = v}` | 同左 | — |
| 调用位置 | `__FILE__`/`__LINE__` 宏 | `std::source_location` | 同左 | — |
| 比较运算 | 手写 `==`/`<` | `= default` 的 `operator<=>`/`operator==` | 同左 | — |
| 容器成员查询/删除 | `find() != end()`、erase-remove | `contains()`、`std::erase_if` | 同左 | — |
| 只移动的可调用对象 | `std::function`（要求可复制） | 同左 | `std::move_only_function` | `absl::AnyInvocable` |

## 接口与参数

| 参数角色 | 写法 |
| --- | --- |
| 小的只读值：整数、枚举、指针、`string_view`、`span` | 按值 |
| 大的只读对象 | `const T&` |
| 要保存的参数（sink） | 按值接收，再 `std::move` 到成员 |
| 输入输出 | `T&` |
| 输出 | 返回值：具名 struct、`Result`、`std::pair` 仅用于含义明显的两个值 |
| 转移独占所有权 | `std::unique_ptr<T>` 按值 |
| 可空的非拥有借用 | `T*` / `const T*`，并在文档里写清寿命 |
| 共享所有权 | 只有接收方确实参与决定寿命时才接收 `std::shared_ptr<T>` |

不写 `const std::unique_ptr<T>&`、`std::shared_ptr<T>&` 这类只为访问对象的参数；直接传 `T&` 或 `T*`。

```cpp
// 旧式：只读数据被迫是 vector，错误通过输出参数返回，构造里先默认构造再赋值
bool Process(const std::vector<uint8_t>& data, std::string* error);
class Parser {
 public:
  Parser(std::string name) { name_ = name; }
};

// 现代：借用任意连续字节，错误随返回值传递，sink 参数按值接收后移动
[[nodiscard]] Result<Summary> Process(std::span<const std::byte> data);
class Parser {
 public:
  explicit Parser(std::string name) : name_(std::move(name)) {}
};
```

返回 `Status`/`Result`/错误码的函数标 `[[nodiscard]]`；项目有对应宏时用宏。查询函数可以标 `[[nodiscard]]`，不必给所有函数都加。

## 所有权与特殊成员

- 不写裸 `new`/`delete`/`malloc`/`free`。独占用 `std::make_unique`，确需共享寿命才用 `std::make_shared`。
- 优先 Rule of Zero：成员都是值、标准容器或 RAII owner 时，不手写任何特殊成员函数。
- 包装 C 句柄优先 `std::unique_ptr` + 删除器 struct，不需要手写整个类：

```cpp
struct FileCloser {
  void operator()(std::FILE* file) const noexcept { std::fclose(file); }
};
using UniqueFile = std::unique_ptr<std::FILE, FileCloser>;
```

  删除器总是写成 struct，包括包装项目自己或第三方的释放函数时：
  - 空的删除器 struct 不占空间，`unique_ptr` 与裸指针一样大；函数指针删除器（`decltype(&CloseRegion)`）要额外存一个指针，在 64 位平台上使 `unique_ptr` 从 8 字节变成 16 字节（libstdc++ 与 libc++ 实测相同）。
  - struct 的调用可以被内联；函数指针删除器在每次释放时多一次间接调用，并且可能被构造成空指针。
  - 对标准库函数还有额外原因：C++20 起取标准库函数的地址不是有保证的行为，`decltype(&std::fclose)` 不可移植。

- 确需自定义 owner 时，同时决定五个特殊成员，移动操作 `noexcept`，moved-from 状态有定义：

```cpp
class FileDescriptor {
 public:
  FileDescriptor() noexcept = default;
  explicit FileDescriptor(int fd) noexcept : fd_(fd) {}
  FileDescriptor(const FileDescriptor&) = delete;
  FileDescriptor& operator=(const FileDescriptor&) = delete;
  FileDescriptor(FileDescriptor&& other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
  FileDescriptor& operator=(FileDescriptor&& other) noexcept {
    if (this != &other) {
      Reset();
      fd_ = std::exchange(other.fd_, -1);
    }
    return *this;
  }
  ~FileDescriptor() { Reset(); }

  [[nodiscard]] int Get() const noexcept { return fd_; }
  [[nodiscard]] bool IsValid() const noexcept { return fd_ >= 0; }
  [[nodiscard]] int Release() noexcept { return std::exchange(fd_, -1); }

 private:
  // 析构路径无法报告 close 失败；需要报告时另提供返回 Status 的显式 Close()。
  void Reset() noexcept {
    if (fd_ >= 0) ::close(fd_);
    fd_ = -1;
  }

  int fd_ = -1;
};
```

- 单参数构造函数和转换运算符默认 `explicit`。覆盖虚函数只写 `override` 或 `final`，不重复 `virtual`。多态基类的析构函数是 `public virtual` 或 `protected` 非虚。
- 成员初始化用默认成员初始化器和初始化列表，不在构造函数体内赋值。

## 错误与转换

- 文本转数字用 `std::from_chars`，不用 `atoi`/`stoi`/`strtol`：它不分配、不依赖 locale、不抛异常，并区分非法输入与越界。

```cpp
enum class ParseError { kEmpty, kInvalid, kOutOfRange };

[[nodiscard]] std::expected<std::uint16_t, ParseError> ParsePort(std::string_view text) {
  if (text.empty()) return std::unexpected(ParseError::kEmpty);
  std::uint16_t port = 0;
  const auto [end, ec] = std::from_chars(text.data(), text.data() + text.size(), port);
  if (ec == std::errc::result_out_of_range) return std::unexpected(ParseError::kOutOfRange);
  if (ec != std::errc{} || end != text.data() + text.size()) {
    return std::unexpected(ParseError::kInvalid);
  }
  return port;
}
```

  C++17/20 项目把 `std::expected` 换成项目的 `Result` 或已引入的同类库，逻辑不变。

- 项目使用异常时：按值抛出、按 `const&` 捕获，不用 `catch (...)` 吞掉错误；只在恢复、转换或终止边界捕获。
- 类型转换用 `static_cast`、`std::bit_cast`（C++20）；`reinterpret_cast` 和 `const_cast` 收敛到可审计的边界。不用 C 风格转换。
- 有符号与无符号混算前先统一类型；大小和下标用 `std::size_t`，需要有符号差值时用 `std::ssize`（C++20）或显式转换。

## 类型与常量

- 常量用 `constexpr`，头文件里的常量用 `inline constexpr`，不用 `#define`。宏只用于条件编译、平台差异和项目既有的日志/断言。
- 枚举用 `enum class`，需要固定大小或序列化时写明底层类型：`enum class Codec : std::uint8_t`。
- 类型别名用 `using`，不用 `typedef`。空指针用 `nullptr`。
- 原始字节用 `std::byte`；时长用 `std::chrono` 类型，不用表示毫秒的裸整数，单位因此出现在类型里。
- 进程级状态：需要延迟初始化时用函数内 `static`（C++11 起线程安全）；C++20 用 `constinit` 保证常量初始化。不写依赖跨编译单元初始化顺序的全局对象。

## 容器、字符串与算法

- 默认 `std::vector`；大小已知时 `reserve`；固定大小用 `std::array`；几乎不需要 `std::list`。哈希表优先项目已用的实现，注意 `absl::flat_hash_map`/`boost::unordered_flat_map` 在 rehash 时元素地址会失效。
- `std::string_view`/`std::span` 只是借用：不要用它们保存会被释放或修改的数据，不要从临时对象构造后保存。
- 用算法和 range-for 表达意图，但不为写成算法而牺牲可读性：

```cpp
// 旧式
bool found = false;
for (int i = 0; i < (int)items.size(); i++) {
  if (items[i].id == id) { found = true; break; }
}
if (map.find(key) != map.end()) { /*...*/ }

// C++20
const bool found = std::ranges::any_of(items, [&](const Item& item) { return item.id == id; });
if (map.contains(key)) { /*...*/ }
std::erase_if(sessions, [](const Session& s) { return s.IsExpired(); });
for (const auto& [name, value] : config) { /*...*/ }
```

- 字符串拼接用 `std::format`/`fmt` 或 `std::string::append`，不用 `std::stringstream` 做简单拼接。换行用 `'\n'`，不用 `std::endl`（它会强制 flush）。
- `emplace_back` 用于原地构造；已经有对象时 `push_back(std::move(x))` 同样合适。

## 模板与编译期

```cpp
// C++17：if constexpr 取代标签分派
template <typename T>
std::string ToText(const T& value) {
  if constexpr (std::is_arithmetic_v<T>) {
    return std::to_string(value);
  } else {
    return std::string(value);
  }
}

// C++20：concepts 写在签名上，错误信息直接指向约束
template <std::unsigned_integral T>
constexpr T AlignUp(T value, T alignment) {
  return (value + alignment - 1) / alignment * alignment;
}
```

- 不为普通函数引入模板；模板只服务于确实需要的泛型。CRTP、表达式模板和元编程只在当前问题需要时使用。
- 模板实现放在头文件；只用于少数已知类型时，可在 `.cc` 中显式实例化以缩短编译时间。

## 并发

- 同时持有多把锁用 `std::scoped_lock(a, b)`；单把锁用 `std::lock_guard`，需要配合条件变量或提前解锁时用 `std::unique_lock`。
- 条件变量总是带谓词等待：`cv.wait(lock, [&] { return ready_; });`。
- C++20 可取消线程用 `std::jthread`：析构时自动请求停止并 join。等待可以被 `stop_token` 打断时用 `std::condition_variable_any`。
- 原子变量默认使用顺序一致内存序；使用 `relaxed`/`acquire`/`release` 时，注释写清配对的同步关系。
- 不用 `volatile` 做线程同步，不用 `sleep` 等待状态，不手写双重检查加锁；一次性初始化用函数内 `static` 或 `std::call_once`。

## AI 常见旧式写法对照

| 常见写法 | 替换为 |
| --- | --- |
| 裸 `new`/`delete`、`malloc`/`free` | `make_unique`、容器、RAII owner |
| 到处 `std::shared_ptr` | 值或 `unique_ptr`；只在确实共享寿命时用 `shared_ptr` |
| 两阶段初始化 `Init()`/`IsInitialized()` | 构造即有效；可失败时用返回 `Result` 的静态工厂 |
| 只有一个实现的接口类 + `Impl` | 具体类；需要替身或多实现时再引入接口 |
| 每个字段都有 getter/setter | 字段独立的数据用 `struct`；有不变量的类只暴露有语义的操作 |
| `Manager`/`Helper`/`Util` 类收集无关函数 | 按职责命名的自由函数或类型 |
| `const std::string&` 参数进来再拷贝保存 | 按值接收后 `std::move` |
| 输出参数 `bool F(T* out)` | 返回 `Result<T>`/`std::optional<T>` |
| `atoi`/`stoi`/`sprintf` | `std::from_chars`、`std::format`/`fmt` |
| `#define` 常量、`typedef`、`NULL` | `constexpr`、`using`、`nullptr` |
| 下标循环 + `int i` | range-for、算法、`std::size_t` |
| `return std::move(local);` | `return local;`（不阻碍拷贝消除） |
| 对 `const` 对象 `std::move` | 去掉 `const` 或直接复制；`const` 对象无法被移动 |
| `catch (...) {}`、`catch (std::exception& e) { log; }` 后继续 | 在有恢复或转换职责的边界处理，保留错误 |
| `std::endl`、`using namespace std;` | `'\n'`、限定名或局部 `using` 声明 |
| 手写 mutex `lock()`/`unlock()` | `lock_guard`/`scoped_lock`/`unique_lock` |
| `std::bind` | lambda |
| 复述代码的注释 | 删除；只写不变量、协议原因与所有权 |
