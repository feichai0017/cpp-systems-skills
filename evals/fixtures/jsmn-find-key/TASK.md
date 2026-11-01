给 jsmn 增加按键查找对象成员的函数：

```c
int jsmn_find(const char *js, const jsmntok_t *tokens, int count, int object, const char *key);
```

在 `tokens[object]` 的直接成员中查找名字等于 `key` 的键（按原始字节比较，不处理转义），返回该键的值令牌的下标；有重复的键时返回第一个。找不到、`tokens[object]` 不是对象，或者这个键后面没有值（jsmn 会接受 `{"a"}` 这样的输入）时返回 -1。

调用方保证：`js` 和 `tokens` 来自同一次成功的 `jsmn_parse`，`count` 是它的返回值，`0 <= object < count`，`key` 是以 NUL 结尾的字符串。补充测试。
