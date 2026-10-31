修复 `LoadHeader` 在头部不合法时泄漏区域的问题。`c_region.h` 不能修改；允许修改 `LoadHeader` 的签名和本目录中的所有调用方，遵循项目现有约定。
