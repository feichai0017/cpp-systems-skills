# 泛型与模板元编程

先判断是否需要泛型，再在项目标准内选择写法。模板写得对，接口约束清楚、错误信息指向调用处、编译时间和代码体积可控；写得不对，就成了只有一个实例化的模板、层层 SFINAE 和难以阅读的元函数。

## 是否使用模板

- 至少有两个实际使用的类型共享同一算法和合同，或者接口本身面向调用方提供的类型（容器、算法、序列化、格式化），才写成模板。只有一个类型时写具体代码；“以后可能支持别的类型”不是理由。
- 类型集合在编译期已知、调用在热路径上时用模板；需要运行时替换、跨共享库或插件边界、控制编译时间和代码体积时，用虚函数或类型擦除（`std::function`、`std::move_only_function`、项目自己的 vtable）；集合封闭且已知时用 `std::variant`。
- 编译期计算用 `constexpr`（C++20 起可用 `consteval`）函数，不用递归模板实例化。
- 先查项目和已引入的库：容器、算法、traits、类型列表（`boost::mp11`）、格式化等通用能力通常已有实现，不自己写一套元编程基础设施。

## 按标准选择写法

| 需求 | C++98/03 | C++11/14 | C++17 | C++20 及以后 |
| --- | --- | --- | --- | --- |
| 限制模板参数 | 注释说明要求，靠实例化报错 | `static_assert`；参与重载时用 `std::enable_if` | 同左，`std::void_t` 检测成员 | concept 写在签名上，`requires` 子句 |
| 按类型选择实现 | 标签分派（如 `iterator_category`） | 标签分派、重载 | `if constexpr` | 受约束的重载，更严格的约束优先 |
| 可变数量参数 | 若干固定参数的重载 | 可变参数模板，递归或数组展开 | 折叠表达式 | 同左 |
| 编译期计算 | 枚举常量、模板递归 | `constexpr` 函数（C++11 只能单个 `return`） | `constexpr` lambda、`if constexpr` | `consteval`、`constinit` |
| 检测类型能力 | `sizeof` 技巧 | `decltype` 加 SFINAE | `std::void_t` | `requires` 表达式 |
| 复用派生类实现 | CRTP | CRTP | CRTP | CRTP；C++23 显式对象参数（deducing this） |

```cpp
// C++20：约束写在接口上，错误信息直接指出不满足的 concept
template <std::integral T>
constexpr T DivideRoundUp(T value, T divisor) {
  return (value + divisor - 1) / divisor;
}

// C++17：没有 concept 时用 static_assert 在第一层报错
template <typename T>
constexpr T DivideRoundUp(T value, T divisor) {
  static_assert(std::is_integral_v<T>, "DivideRoundUp requires an integer type");
  return (value + divisor - 1) / divisor;
}

// C++17：折叠表达式取代递归展开
template <typename... Parts>
std::size_t TotalSize(const Parts&... parts) {
  return (std::size_t{0} + ... + parts.size());
}
```

- `static_assert` 表达“只能这样用”；`enable_if` 或 concept 用于在多个重载之间选择。不要用 SFINAE 实现本来一个 `if constexpr` 就能写清的分支。
- concept 表达语义要求，优先组合标准 concept（`std::integral`、`std::ranges::input_range`、`std::invocable`）；不写成照抄函数体的 `requires { x.a(); x.b(); }` 清单。只被一个模板使用的约束直接写 `requires` 子句，不另起名字；需要命名时用名词或形容词，如 `ByteSink`。
- 模板参数尽量少，能推导的不要求调用方写。策略参数（allocator、比较器、锁）只在已经有两种以上实际策略时引入。
- 转发引用配 `std::forward`，只读参数用 `const T&`，要保存的参数按值接收再移动。不对非转发引用调用 `std::forward`。
- 类型萃取用 `<type_traits>`；自定义 trait 时同时提供 `_v`/`_t` 别名（C++17/14）。
- 表达式模板、类型列表、编译期状态机只在已引入的库无法满足、且有测量收益时才自己写。

## 运行时选择与编译期参数

运行时才知道的选择（单位、格式、类型标签）只在一处分派：每个分支用编译期参数调用同一个模板，模板内部的比例、约分和范围都是编译期常量，由 `std::ratio_divide`、`std::numeric_limits` 等标准设施给出。不要把编译期已知的分子分母读成运行时变量，再手写最大公约数、约分和溢出判断。比例相乘溢出时 `std::ratio_divide` 编译失败，这和 `duration_cast` 的限制一致，是可以接受的边界；不为没有调用方的极端周期改写成运行时实现。

```cpp
// 分支只决定单位；比例在编译期约分，范围来自 numeric_limits。
// <ratio> 从 C++11 起可用，旧标准下把 optional 换成项目的错误方式。
template <typename From, typename To>
std::optional<long long> Rescale(long long count) {
  using R = std::ratio_divide<From, To>;  // R::num / R::den 已约分
  if (count % R::den != 0) return std::nullopt;  // 结果不是整数
  const long long q = count / R::den;
  if (q > std::numeric_limits<long long>::max() / R::num ||
      q < std::numeric_limits<long long>::min() / R::num) return std::nullopt;
  return q * R::num;
}

switch (unit) {
  case Unit::kKilo: return Rescale<std::kilo, std::milli>(count);
  case Unit::kUnit: return Rescale<std::ratio<1>, std::milli>(count);
}
```

## 头文件、编译时间与 ABI

- 模板定义放在头文件；实现细节放 `detail` 命名空间或 `-inl.h` 文件，见 [项目结构与文件摆放](project-layout.md)。
- 实例化类型有限时，在头文件中写 `extern template` 声明，在一个 `.cc` 中显式实例化，减少重复编译。
- 把不依赖模板参数的代码提到非模板函数中，减少代码膨胀；大的模板类可以把与类型无关的部分放进非模板基类。
- 模板和 `inline` 函数的改动会编进调用方的二进制，改变已发布头文件中的模板行为属于 ABI 变化，见 [ABI 与跨语言互操作](abi-and-interop.md)。

## 常见过度写法对照

| 写法 | 替换为 |
| --- | --- |
| 只有一个类型实例化的模板 | 具体函数或类 |
| 用 `enable_if` 链区分整数、浮点和字符串 | `if constexpr`，或 concept 约束的几个重载 |
| 用递归模板计算编译期常量 | `constexpr` 函数 |
| 只有一种策略的策略类模板参数 | 直接写这一种策略 |
| 为了“通用”把容器类型作为模板参数 | 接收 `std::span`、迭代器对或范围 |
| 只包装一个类型的类型擦除 | 直接使用该类型 |
| 手写类型列表和元函数 | 已引入的 `boost::mp11`，或直接用 `std::variant`/`std::tuple` |
| 为了零开销把所有接口都写成模板 | 只在热路径上测得收益的地方用模板，其余用普通函数 |
| 运行时读出编译期已知的比例，再手写最大公约数、约分和溢出判断 | 在分派处把单位作为模板参数，比例交给 `std::ratio_divide`，范围用 `std::numeric_limits` |

## 验证

- 每个支持的类型都至少实例化一次；对 concept 和 `static_assert` 约束，用 `static_assert(!std::integral<double>)` 一类的编译期断言确认不该接受的类型被拒绝。
- 在项目支持的最低标准和全部编译器上编译；GCC、Clang、MSVC 在 SFINAE、concept 和两阶段查找的细节上并不一致。
- 关注编译时间时用 Clang 的 `-ftime-trace` 或 GCC 的 `-ftime-report` 找出开销最大的实例化，不凭感觉重写模板。
