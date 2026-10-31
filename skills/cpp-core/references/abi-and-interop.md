# ABI 与跨语言互操作

发布共享库、插件接口，提供 C 接口，或与 Python、Rust、其他编译产物交互时阅读。只在单一构建内部使用的静态库，不需要承担 ABI 稳定的成本。

## 先确定兼容承诺

写清楚哪些接口承诺二进制兼容（ABI）、哪些只承诺源码兼容（API）、哪些完全不承诺。没有承诺的内部接口不要为兼容付出代价；有承诺的接口每次修改都按下面的清单检查。

## 会破坏 ABI 的修改

- 增删或重排类的非静态成员、改变成员类型，导致 `sizeof`、对齐或偏移变化。
- 增删、重排虚函数，或改变虚函数签名。
- 修改 `inline` 函数、模板或 `constexpr` 函数的行为：调用方已经把旧实现编译进自己的二进制。
- 改变函数参数或返回类型、`noexcept` 规格（C++17 起属于函数类型的一部分）、调用约定。
- 改变枚举的底层类型，或改变已发布枚举值的数值。
- 用不同的标准库 ABI 设置编译：libstdc++ 的 `_GLIBCXX_USE_CXX11_ABI` 不同时，`std::string`、`std::list` 的布局不同，跨库传递会出错。

需要长期稳定的 C++ 类用 Pimpl（见设计范式参考），公开头文件只暴露指向实现的指针。

## 共享库与符号

- 默认隐藏符号，只导出公开 API（GCC/Clang 的 `-fvisibility=hidden` 加导出宏；CMake 的 `CXX_VISIBILITY_PRESET hidden` 与 `GenerateExportHeader`）。这能减少符号冲突、加快加载，并让 ABI 范围一目了然。
- 用 soname 表达 ABI 版本（`libkvstore.so.1`），不兼容的修改提升主版本。
- 在共享库边界上，由同一个库负责分配和释放同一块内存；不要让一个库 `new` 的对象由另一个库 `delete`，除非两边使用同一个标准库和分配器。
- 跨共享库传递 `std::string`、`std::vector` 等标准类型的前提是两边使用相同的编译器、标准库版本与 ABI 设置。做不到时在边界上使用 C 类型或项目自己的稳定类型。
- 同一个类型或全局对象不要在多个共享库中各有一份定义（ODR 违规），这会导致静态对象被初始化两次或 `dynamic_cast` 失败。
- API 有多个版本并存时，可以用 `inline namespace v1` 给符号加版本，旧版本保留在非内联命名空间中。

## C 接口

对外提供 C 接口时，用不透明句柄和错误码，C++ 的异常与类型不越过边界：

```cpp
// kvstore_c.h —— 必须能被 C 编译器编译，并且自包含
#ifndef KVSTORE_C_H_
#define KVSTORE_C_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct kv_store kv_store;   /* 不透明句柄 */

/* 成功返回 0，失败返回正的 errno 风格错误码。 */
int kv_store_open(const char* path, kv_store** out);
int kv_store_get(kv_store* store, const char* key, char* value, size_t capacity, size_t* written);
void kv_store_close(kv_store* store);

#ifdef __cplusplus
}
#endif

#endif  /* KVSTORE_C_H_ */
```

```cpp
// kvstore_c.cc
struct kv_store {
  std::unique_ptr<kvstore::Store> impl;
};

extern "C" int kv_store_open(const char* path, kv_store** out) {
  if (path == nullptr || out == nullptr) return EINVAL;
  try {
    auto store = kvstore::Store::Open(path);
    if (!store.ok()) return ToErrno(store.status());
    *out = new kv_store{std::make_unique<kvstore::Store>(std::move(store).value())};
    return 0;
  } catch (const std::bad_alloc&) {
    return ENOMEM;
  } catch (...) {
    return EIO;   // 异常不能穿过 C 边界
  }
}

extern "C" void kv_store_close(kv_store* store) { delete store; }
```

- C 边界上由 `kv_store_close` 负责释放，这是 C 接口中少数必须写 `new`/`delete` 的地方，收敛在这一个文件里。
- 输出缓冲区由调用方提供并传入容量；容量不足时返回需要的大小，而不是截断数据。
- 回调函数指针带一个 `void* user_data` 参数，并写清回调在哪个线程、何时被调用、何时不再被调用。

## 插件与动态加载

- `dlopen` 加载的插件导出一个 C 函数，返回包含版本号和函数表的结构体；加载时先检查版本，再使用其他符号。
- 卸载插件（`dlclose`）前，确认没有线程仍在执行插件代码、没有回调或 `thread_local` 对象仍引用它。很多项目选择从不卸载插件，这是合理的简化。
- 插件和宿主之间不传递需要对方析构的 C++ 对象，除非双方由同一构建产物编译。

## Python 绑定

- 用 pybind11 或 nanobind。长时间运行或阻塞的 C++ 调用前释放 GIL（`py::gil_scoped_release` / `nb::gil_scoped_release`），并且在释放 GIL 期间不触碰任何 Python 对象。
- 返回指向 C++ 内部数据的对象时，明确所有权：拷贝、转移给 Python，或者通过 keep-alive 让 Python 对象持有其父对象。缓冲区协议暴露的内存，必须在 Python 端视图存在期间保持有效。
- C++ 异常在绑定层转换为 Python 异常；从 C++ 线程回调 Python 时，先重新获取 GIL。
- 扩展模块的 Python 版本与 ABI 矩阵（是否使用稳定 ABI、支持的解释器版本）写进构建配置。

## Rust 互操作

- 用 cxx crate 生成双方都安全的桥接代码，或手写 C 接口加不透明指针。
- 所有权跨越边界时，指定由哪一边释放，并提供对应的释放函数；Rust 的 `Box` 和 C++ 的 `unique_ptr` 不能直接互相释放。
- Rust 的 panic 和 C++ 的异常都不能穿过 FFI 边界，在各自一侧捕获并转换成错误码。
