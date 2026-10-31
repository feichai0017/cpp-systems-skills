# CUDA C++

编写或修改 CUDA host 代码、kernel、GPU 内存与 stream 管理时阅读。设备内存与主机内存之间的寿命、DMA 与 IPC 完成合同属于 `cpp-lifetime` 技能的跨边界参考。

## 资源所有权

- stream、event、设备内存、pinned 主机内存、IPC 映射都由 RAII owner 持有，析构时释放；释放前确认没有尚未完成的异步操作仍在使用该资源。
- 可以用 `std::unique_ptr` 加删除器 struct 包装设备指针：

```cpp
struct DeviceFree {
  void operator()(void* ptr) const noexcept { cudaFree(ptr); }
};
using DeviceBuffer = std::unique_ptr<void, DeviceFree>;

struct StreamDestroy {
  void operator()(cudaStream_t stream) const noexcept { cudaStreamDestroy(stream); }
};
using UniqueStream = std::unique_ptr<std::remove_pointer_t<cudaStream_t>, StreamDestroy>;
```

- 析构路径无法报告释放失败；需要知道异步错误时，在释放前显式同步并检查错误。

## 错误检查

- 每个 CUDA runtime/driver 调用都检查返回值，并转换成项目的 `Status`，而不是 `exit` 或只打印：

```cpp
[[nodiscard]] inline Status CudaStatus(cudaError_t error, std::string_view what) {
  if (error == cudaSuccess) return Status::Ok();
  return Status::Internal(std::string(what) + ": " + cudaGetErrorString(error));
}
```

- kernel 启动本身不返回错误：启动后用 `cudaGetLastError()` 检查配置错误；执行中的错误要在之后的同步点（`cudaStreamSynchronize`、`cudaEventSynchronize`）才能观察到。
- 部分错误（例如非法地址访问）会使整个 CUDA 上下文失效，之后的调用都会失败；这类错误按致命错误处理。

## Stream 与同步

- 不依赖传统默认 stream 的隐式同步。使用显式创建的 stream，或用 `--default-stream per-thread` 编译。
- 跨 stream 的依赖用 event 表达：生产者 stream 上 `cudaEventRecord`，消费者 stream 上 `cudaStreamWaitEvent`，而不是在主机上同步整个设备。
- 主机等待 GPU 结果时只同步需要的 stream 或 event；`cudaDeviceSynchronize` 只用于测试或关闭流程。
- 每个线程使用 GPU 前调用 `cudaSetDevice`，当前设备是线程局部的状态。

## 内存

- 异步的主机与设备拷贝需要 pinned 主机内存（`cudaHostAlloc`，或对已有内存 `cudaHostRegister`）；对普通分页内存调用 `cudaMemcpyAsync` 会退化为同步拷贝。
- 频繁的设备分配使用 stream 有序的分配器（`cudaMallocAsync`/`cudaFreeAsync`）或内存池，避免 `cudaMalloc`/`cudaFree` 的全局同步开销。
- 释放仍被异步操作使用的内存是未定义行为：先在对应 stream 上记录 event 并等待，或使用 stream 有序释放。
- CUDA IPC 句柄的导出方必须在导入方完成所有访问并关闭句柄之后才能释放内存。

## Kernel 编写

- 用 grid-stride 循环处理任意大小的输入；索引计算使用足够宽的整数类型，避免大张量下溢出。
- 设备代码中避免分支发散和非合并访存；访存模式按 warp 组织。
- 优先使用现成的库：CCCL（Thrust、CUB、libcu++）提供扫描、归约、排序等原语，CUTLASS 提供 GEMM 与张量核心模板。

## 代码组织

- `.cu`/`.cuh` 与纯主机代码分开；公开的主机头文件不 include CUDA 头文件，必要时用 Pimpl 或不透明句柄隐藏 `cudaStream_t` 等类型（见项目结构参考）。
- CUDA graph 捕获期间禁止同步和某些分配操作；被捕获的代码路径要单独测试。

## 验证与剖析

- `compute-sanitizer` 的 memcheck、racecheck、initcheck、synccheck 分别检查越界访问、共享内存竞争、未初始化读取和同步错误。
- 性能用 Nsight Systems 看整体时间线（拷贝、kernel、同步的重叠），Nsight Compute 分析单个 kernel。
- 数值结果与 CPU 参考实现或高精度实现对比，容差按数据类型和算法写明。
