给 utf8proc 增加计算 UTF-8 字符串显示宽度的函数：

```c
utf8proc_ssize_t utf8proc_strwidth(const utf8proc_uint8_t *str, utf8proc_ssize_t strlen);
```

返回 `str` 中逐个码点的 `utf8proc_charwidth` 之和。`strlen` 不小于 0 时读取 `strlen` 个字节；`strlen` 为负数时 `str` 以 NUL 结尾，读到 NUL 为止。遇到无效的 UTF-8 时返回 `UTF8PROC_ERROR_INVALIDUTF8`。补充测试。
