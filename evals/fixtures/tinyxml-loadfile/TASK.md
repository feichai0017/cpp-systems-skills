`TiXmlDocument::LoadFile(FILE*, TiXmlEncoding)` 又长又难维护：获取文件大小、读取、换行规范化和解析全写在一个函数里，错误路径要手动释放缓冲区，`fseek`/`ftell` 的失败也没有处理。重构它，保持公开接口和已有行为不变。
