#pragma once

#include <coroutine>
#include <deque>
#include <exception>
#include <optional>
#include <system_error>
#include <utility>
#include <vector>

namespace project {

// Runs scheduled coroutines when RunUntilIdle is called.
class ManualExecutor {
public:
    struct ScheduleAwaiter {
        ManualExecutor& executor;
        bool await_ready() const noexcept { return false; }
        void await_suspend(std::coroutine_handle<> handle) { executor.ready_.push_back(handle); }
        void await_resume() const noexcept {}
    };

    // Suspends the caller; it resumes later from RunUntilIdle.
    ScheduleAwaiter Schedule() { return ScheduleAwaiter{*this}; }

    void RunUntilIdle() {
        while (!ready_.empty()) {
            const std::coroutine_handle<> handle = ready_.front();
            ready_.pop_front();
            handle.resume();
        }
    }

private:
    std::deque<std::coroutine_handle<>> ready_;
};

template <typename T>
class Task;

// Starts the task, drives the executor until it is idle and returns the result.
template <typename T>
T SyncWait(ManualExecutor& executor, Task<T> task);

// Lazy task: the body starts when the task is awaited.
template <typename T>
class [[nodiscard]] Task {
public:
    struct promise_type {
        std::optional<T> value;
        std::coroutine_handle<> continuation;

        Task get_return_object() { return Task(std::coroutine_handle<promise_type>::from_promise(*this)); }
        std::suspend_always initial_suspend() noexcept { return {}; }

        struct FinalAwaiter {
            bool await_ready() noexcept { return false; }
            std::coroutine_handle<> await_suspend(std::coroutine_handle<promise_type> handle) noexcept {
                const std::coroutine_handle<> next = handle.promise().continuation;
                return next ? next : std::noop_coroutine();
            }
            void await_resume() noexcept {}
        };
        FinalAwaiter final_suspend() noexcept { return {}; }

        void return_value(T result) { value = std::move(result); }
        void unhandled_exception() noexcept { std::terminate(); }
    };

    Task(Task&& other) noexcept : handle_(std::exchange(other.handle_, {})) {}
    Task& operator=(Task&& other) noexcept {
        if (this != &other) {
            if (handle_) handle_.destroy();
            handle_ = std::exchange(other.handle_, {});
        }
        return *this;
    }
    Task(const Task&) = delete;
    Task& operator=(const Task&) = delete;
    ~Task() {
        if (handle_) handle_.destroy();
    }

    bool await_ready() const noexcept { return false; }
    std::coroutine_handle<> await_suspend(std::coroutine_handle<> awaiting) noexcept {
        handle_.promise().continuation = awaiting;
        return handle_;
    }
    T await_resume() { return std::move(*handle_.promise().value); }

private:
    template <typename U>
    friend U SyncWait(ManualExecutor& executor, Task<U> task);

    explicit Task(std::coroutine_handle<promise_type> handle) : handle_(handle) {}

    std::coroutine_handle<promise_type> handle_;
};

template <typename T>
T SyncWait(ManualExecutor& executor, Task<T> task) {
    task.handle_.resume();
    executor.RunUntilIdle();
    if (!task.handle_.done()) std::terminate();
    return std::move(*task.handle_.promise().value);
}

// Awaits the tasks one by one and returns the first error.
inline Task<std::error_code> AwaitAll(std::vector<Task<std::error_code>> tasks) {
    std::error_code first;
    for (Task<std::error_code>& task : tasks) {
        const std::error_code error = co_await std::move(task);
        if (error && !first) first = error;
    }
    co_return first;
}

}  // namespace project
