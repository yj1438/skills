# Reference 示例

这个目录存放 skill 正文的"第二层细节"：agent 按需才读取，不占用主上下文。

适合放：

- 完整的参数/字段表
- 长篇示例与模板
- 边缘情况的详细处理

写作建议：每个文件聚焦一个主题，文件名即主题（如 `styles.md`、`api-fields.md`）。
避免 skill 正文 → reference → 另一个 reference 的多跳引用（超过一跳难以被发现）。
