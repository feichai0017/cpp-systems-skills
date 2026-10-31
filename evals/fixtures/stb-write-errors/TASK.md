用户报告：磁盘写满时 `stbi_write_png` 仍然返回 1，留下一个被截断的 PNG 文件，调用方以为图片已经保存成功。`stb_image_write.h` 的说明写明 “Each function returns 0 on failure and non-0 on success.”，请修复写文件失败时的返回值。
