给 `DoubleToStringConverter` 增加十六进制浮点输出：

```cpp
bool ToHexadecimal(double value, StringBuilder* result_builder) const;
```

输出 C99 `%a` 风格的小写表示，尾数去掉末尾的 0：规范数写成 `0x1.<十六进制小数>p<指数>`，小数部分为 0 时省略小数点（例如 `1.0` 为 `0x1p+0`，`3.0` 为 `0x1.8p+1`，`0.1` 为 `0x1.999999999999ap-4`）；次正规数写成 `0x0.<十六进制小数>p-1022`；零写成 `0x0p+0`。指数用十进制，总是带符号。负数、负零、无穷和 NaN 的处理以及返回值都与 `ToShortest` 相同。补充测试。
