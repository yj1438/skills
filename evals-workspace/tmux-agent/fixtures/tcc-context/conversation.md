# 当前方案

- tmux Claude session 稳定命名为 `tc-<项目名>-<分支名>`。
- 没有分支或处于 detached HEAD 时，分支部分使用 `main`。
- 为避免 tmux 名称转换或 target 解析歧义，依次把 `%` 编码为 `%25`、`.` 编码为 `%2E`、`:` 编码为 `%3A`。
- 用户可以主动 attach 进入会话；只有用户明确要求时才 destroy，会话不会在任务完成或超时后自动销毁。
