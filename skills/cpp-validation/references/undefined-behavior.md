# 未定义行为

排查只在特定优化级别、编译器或负载下出现的问题，或审查容易出现未定义行为的代码时阅读。未定义行为不保证会崩溃，编译器可以假设它不会发生并据此优化，所以“测试通过”不能证明没有问题。

## 常见类别与检测方式

| 类别 | 例子 | 检测 | 修正 |
| --- | --- | --- | --- |
| 越界访问 | `vec[i]` 中 `i >= size()`；读取超出缓冲区 | ASan；`-D_GLIBCXX_ASSERTIONS` | 在边界检查长度；用 `span` 和范围算法 |
| use-after-free / 悬垂引用 | 返回局部对象的引用；`string_view` 指向临时 `string`；迭代器在扩容后使用 | ASan；`-Wdangling`（Clang）、`-Wdangling-reference`（GCC 13+） | 明确 owner 与借用期限 |
| 有符号整数溢出 | `int` 相加超出范围 | UBSan `-fsanitize=signed-integer-overflow` | 先检查范围，或使用更宽的类型 |
| 非法移位 | 移位量大于等于位宽；C++20 之前左移负数 | UBSan `-fsanitize=shift` | 检查移位量 |
| 违反严格别名 | 通过 `uint32_t*` 读取 `float` | 难以检测；`-Wstrict-aliasing` 只能发现部分 | `std::bit_cast`、`std::memcpy` |
| 未对齐访问 | 把任意字节偏移强转为 `uint64_t*` | UBSan `-fsanitize=alignment` | `std::memcpy` 到局部变量 |
| 读取未初始化内存 | 未初始化的局部变量或成员 | MSan；`-Wuninitialized`、`-Wmaybe-uninitialized` | 默认成员初始化器，声明即初始化 |
| 数据竞争 | 两个线程无同步地读写同一变量 | TSan | 锁或原子变量 |
| 空指针解引用 | 未检查返回值 | UBSan `-fsanitize=null`；ASan | 在接口上表达可空性 |
| 对象生命周期 | 在原始缓冲区上访问未构造的非平凡对象 | ASan 只能发现部分 | placement new 构造、显式析构 |
| ODR 违规 | 同名类在两个编译单元中定义不同；同一静态库被链接进两个共享库 | ASan 的 `detect_odr_violation`；LTO 下的 `-Wodr` | 一个定义，一个归属库 |
| 静态初始化顺序 | 全局对象的构造依赖另一个编译单元的全局对象 | ASan 的 `check_initialization_order` | 函数内 `static` 或 `constinit` |
| 无副作用的无限循环 | 没有 I/O、volatile 或原子操作的死循环 | 难以检测 | 循环中等待真正的事件 |

## 容易混淆的情况

- “实现定义”和“未指定”行为不是未定义行为，但同样不可移植：`char` 的符号、`int` 的位宽、右移负数的结果（C++20 前）、函数参数的求值顺序。依赖它们的代码写明前提或改为可移植的写法。
- 使用已被移动的对象不是未定义行为（标准类型处于有效但未指定的状态），但通常是逻辑错误；clang-tidy 的 `bugprone-use-after-move` 可以发现。
- `-fno-strict-aliasing` 和 `-fwrapv` 让一部分未定义行为变为确定行为，但它们是项目级的选择，不是修复个别缺陷的手段。

## 排查步骤

1. 用 ASan+UBSan 构建运行失败的场景；数据竞争嫌疑时用 TSan 单独构建。
2. 对比 `-O0` 与 `-O2`、GCC 与 Clang 的行为差异；只在某个优化级别出现的问题往往是未定义行为。
3. 打开更多警告（`-Wall -Wextra`，以及上表中的专项警告），并运行 clang-tidy 的 `bugprone-*` 检查。
4. 把问题缩小到最小复现，修复后保留回归测试，并在 sanitizer 构建中运行。

sanitizer 只能发现被执行到的路径上的问题；没有被测试覆盖的路径仍可能有未定义行为。
