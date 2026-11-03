批量写入 `WriteBatch` 在 AddressSanitizer 下报告 heap-use-after-free，线上也偶尔写入乱码的 key。修复这个问题。
