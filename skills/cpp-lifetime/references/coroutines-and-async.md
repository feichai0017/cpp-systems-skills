# 协程与异步模型

编写或审查 C++20 协程、future/promise、回调链或执行器相关代码时阅读。沿用项目已有的异步运行时（`folly::coro`、Asio 的 awaitable、Seastar、项目自研的 Task 类型），不自行实现 promise 类型，除非项目确实没有可用实现。

## 协程帧与参数寿命

协程在第一次挂起后，调用方的栈帧可能已经返回。协程帧只保存参数的副本（按值参数）或引用（引用参数）本身：

```cpp
// 有问题：name 是对调用方临时对象的引用，挂起后可能已销毁
Task<Status> Store::Put(const std::string& name, std::span<const std::byte> value) {
  co_await lock_.Acquire();
  co_return Write(name, value);    // name 与 value 可能已经悬垂
}

// 修复：需要跨越挂起点的数据按值接收，或由调用方保证在 co_await 完成前一直存活
Task<Status> Store::Put(std::string name, std::vector<std::byte> value) {
  co_await lock_.Acquire();
  co_return Write(name, value);
}
```

- 跨越 `co_await` 的引用、`string_view`、`span` 和裸指针都要证明被引用对象在协程完成前存活；不能证明时按值传入。
- 协程 lambda 的捕获存放在 lambda 对象里，而不是协程帧里。lambda 对象销毁后，协程中通过捕获访问的数据就悬垂了。把 lambda 存活到协程结束，或者把需要的值作为参数按值传入。
- `this` 也是一个引用：成员协程挂起期间对象被销毁会导致悬垂。对象的关闭流程必须等待所有成员协程完成。

## 结构化并发

- 每个启动的协程都有一个 owner 等待它完成（`co_await`、任务组或作用域对象）。不写没有 owner 的“发射后不管”协程；确需后台任务时，把它交给一个在关闭时会取消并等待的作用域。
- 父任务返回前，所有子任务都已完成或被取消并确认结束。这样资源的寿命可以按词法作用域推理。
- 并发等待多个任务用运行时提供的组合（例如 `folly::coro::collectAll`、Asio 的 `operator&&`/`experimental::make_parallel_group`），并定义其中一个失败时其他任务如何取消。

## 取消与超时

- 取消通过显式的令牌或运行时的取消机制传播（`std::stop_token`、`folly::CancellationToken`、Asio 的 cancellation slot），每个挂起点都能响应取消。
- 超时通常实现为“工作”与“计时器”竞争，先完成的一方取消另一方。被取消的操作可能已经部分完成，调用方需要知道它的状态，而不是假设什么都没发生。
- 取消请求不代表底层 I/O 已经停止：等待被取消操作的完成通知后，才能释放它使用的缓冲区。

## 线程与执行器

- 协程恢复时可能在另一个线程上运行（取决于执行器）。挂起点之前获取的线程局部状态、非线程安全对象的访问要按“可能换线程”来检查。
- 不要在持有 `std::mutex` 的情况下 `co_await`：恢复时可能在另一个线程上解锁，这是未定义行为。用运行时提供的异步互斥锁，或在挂起前释放锁。
- 阻塞调用（同步 I/O、长时间计算、等待条件变量）不要放在事件循环线程上的协程里；交给专门的线程池执行并 `co_await` 结果。

## 异常与错误

- 协程中未处理的异常由 promise 的 `unhandled_exception` 处理，通常在 `co_await` 结果时重新抛出。无异常项目使用返回 `Status`/`Result` 的任务类型。
- 被丢弃的任务（没有人 `co_await`）中的错误会被静默忽略；用 `[[nodiscard]]` 标注任务类型，并在审查中检查每个任务的结果是否被使用。

## 回调、future 与迁移

- 回调式接口要写清回调在哪个线程、以什么顺序、最多调用几次，以及注销后是否还可能被调用。
- 从回调迁移到 future 或协程时，保持原有的寿命合同：原来由回调结束时释放的资源，迁移后要在任务完成时释放，而不是在提交时。
- C++26 的 `std::execution`（senders/receivers）提供标准化的异步组合；在标准库和项目工具链支持之前，使用项目已有的运行时。

## 验证

- 用可控的执行器（手动驱动、单线程）复现挂起点前后的交错，测试取消、超时和对象关闭时仍有在途任务的情况。
- ASan 能发现协程帧中悬垂引用导致的 use-after-free；TSan 能发现跨线程恢复引起的数据竞争。
