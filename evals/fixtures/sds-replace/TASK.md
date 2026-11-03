给 sds 增加替换函数：

```c
sds sdsreplace(sds s, const char *from, size_t fromlen, const char *to, size_t tolen);
```

从左到右把 `s` 中所有不重叠出现的 `from`（`fromlen` 字节）替换成 `to`（`tolen` 字节），二进制安全；`fromlen` 为 0 时 `s` 不变。和 `sdscatlen` 等函数一样，调用之后只能使用返回的指针；内存不足时返回 NULL。补充测试。
