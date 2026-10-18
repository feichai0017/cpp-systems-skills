修复 RunOperation：调用返回后，SlotPool 应能继续接收下一次操作。保留 bool 返回值的含义，检查成功和失败后的行为，沿用项目现有约定。
