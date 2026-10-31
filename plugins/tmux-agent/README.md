# tmux-agent

连接本机 Claude Code、Codex 的 CLI 与 Code App 会话。2.1.1 保留现有 tmux CLI 流程，增加 App 会话发现、精确投递和一次结果回信。调用方明确选择接收方；CLI 在同一项目分支复用受管会话。

```text
tcc 理解和 CR 一下当前未提交的变更
to claude 你觉得上面的方案怎么样
tcx CR 一下当前变更
to codex 按上面的方案实现，修改范围限于 src/cache
列出 Codex App 会话，让我选一个问问题
把结果发给 Claude Desktop 的 Code 会话“接口评审”，完成后回信到本会话
```

调用侧会展开“上面”等上下文，按咨询、只读评审、授权实现、状态或移交生成消息。默认接收方完成后回传，不递归转交；共享工作区写任务串行。

## 安装

```text
/plugin marketplace add yj1438/skills
/plugin install tmux-agent@yj-skills
```

Codex 用户沿用仓库首页的 Marketplace 安装方式；本次变更合入并推送后，已安装用户按原渠道更新并确认版本为 2.1.1。

## App 投递与反馈

接收方决定通道，请求和结果回信使用同一路由：

| 组合 | 问题投递与接收 | 结果返回与接收 |
| --- | --- | --- |
| Claude CLI ↔ Codex CLI | tmux → 目标受管 pane | 调用方 capture 读取目标完整结果 |
| Claude CLI → Codex App | queue → 目标 thread UUID | tmux → 原 Claude pane |
| Codex CLI → Claude App | inbox → 目标本机 Code 会话 | tmux → 原 Codex pane |
| Claude App → Codex App | queue → 目标 thread UUID | inbox → 原 Claude Code 会话 |
| Codex App → Claude App | inbox → 目标本机 Code 会话 | queue → 原 Codex thread |

App 都指本机 Code 会话，CLI 都指 tmux-agent 管理的会话。`tcc` / `tcx` 仍选择 CLI；App 需要明确指定。目标不明确或重名时列出标题、目录、时间供用户选择，不选最近或按项目猜选。请求携带编号与准确回信地址；收到结果只结束本次交互。

```bash
SKILL_DIR="<skill_dir>"
bash "$SKILL_DIR/scripts/tmux-agent.sh" codex-app list --search "标题"
bash "$SKILL_DIR/scripts/tmux-agent.sh" claude-app list
bash "$SKILL_DIR/scripts/tmux-agent.sh" codex-app address "<原会话 UUID>"
# REPLY_TO 为原调用会话的 address JSON；正文从 stdin 输入。
bash "$SKILL_DIR/scripts/tmux-agent.sh" codex-app send "<目标 UUID>" --reply-to "$REPLY_TO"
```

CLI 调用方在原工作区用 `claude address <target>` / `codex address <target>` 获取回信地址。接收方处理完成后用 `reply --envelope "$REQUEST"` 回信；回 CLI 前先用 `address <原 pane_id>` 获取当前坐标，再 capture 确认空闲并增加 `--confirm-idle`。Helper 使用稳定 pane ID，在实际粘贴前由 tmux 服务端核验 PID、原生 ID 和前台进程，不向同名重建会话改投；窗口重编号可继续回信。

`queued` 只表示 queue 已入队；`submitted` 只表示写入，均不代表目标已接收或处理完成。超时、异常回执或部分写入按 unknown 处理，不自动重试。Claude inbox 的 held/refused 规则保持有效，不修改全局设置或借用会话 token。

未加载的 Codex App 会话可能要打开后才消费队列；需要唤起目标时显式使用 `codex-app send ... --open`。它在入队成功后打开准确会话链接，打开失败也不重复投递，不把打开视图当作处理完成。

Codex 列表来自本机非归档存储历史，不是当前打开窗口清单；Claude 列表只包含已登记且存活的 Desktop Code inbox。用户明确选择新建时可创建 Codex 本机持久会话，Helper 不承诺自动在桌面打开；Claude Desktop 的新建需在 App 完成，不能用 CLI 冒充。完整参数、反馈流程和边界见 [App 桥接说明](references/app-bridge.md)。

App Helper 需要 Python 3.10+；Codex 需支持 app-server 元信息协议和 queue，Claude inbox 当前仅适配 macOS/Linux peerProtocol=1 的本机 Desktop Code 登记。无新增 MCP 或常驻桥接服务，不支持普通聊天、云端/SSH/容器 App 会话。Claude wire 与会话登记尚非稳定 SDK 契约，版本不兼容时失败，不猜测目标。隔离测试与真实 Desktop 验证分别记录，不能以脚本测试宣称所有往返已实测。

入口会从已安装的 python3 / python3.14 至 python3.10 选择受支持版本，也可用 TMUX_AGENT_PYTHON 显式指定；不会修改全局解释器。状态以 stdout JSON 为准：failed=1、unknown=3、pending=4。Claude 进程启动时间统一按 C locale / UTC 比对。

2.1.0 已在本机完成一次真实 Claude CLI → Codex App → 原 Claude CLI 往返，包含请求编号关联、准确原地址和中文多行结果。涉及 Claude Desktop 的三组尚未完成真实端到端测试；不将隔离 socket 测试算作 Desktop 通过。模型级原生 eval 尚未运行。

## CLI 命令与会话

```bash
SKILL_DIR="<skill_dir>" # tmux-agent 插件根目录
AGENT=codex            # 或 claude
SESSION=$("$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" name "$PWD")
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" list
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" start "$PWD"
TARGET=$("$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" target "$SESSION")
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" capture "$TARGET" 120
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" send "$TARGET" "请只读评审当前未提交变更"
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" status "$TARGET"
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" attach "$SESSION"
```

多行消息可通过 stdin 交给一次 `send`，Helper 使用 bracketed paste 并只提交一次。名称、项目边界、归属和传输共用公共层，启动及 CLI 差异由适配器实现。`list` 显示 tmux 全部 pane，managed/权限/原生 ID 字段按所选适配器展示，必须按完整名称定位。

| 目标 | 入口 | 稳定名称 | 启动与读取规则 |
| --- | --- | --- | --- |
| Claude Code | `tcc` / `to claude` | `tc-<项目>-<分支>` | [Claude 适配](references/claude-cli.md) |
| Codex | `tcx` / `to codex` | `ta-codex-<项目>-<分支>` | [Codex 适配](references/codex.md) |

项目名取 Git 根目录名，非 Git 目录取规范化 cwd；无分支或 detached HEAD 用 main。`%`、`.`、`:` 依次编码为 `%25`、`%2E`、`%3A`。真实名称必须通过 Helper 得到，假设场景用 `format-name <project> <branch>`，不手算。不同 checkout 的同名项目/分支发生名称碰撞时拒绝接管，不自动换用其它会话。

## CLI 结果与可见入口

初次成功创建及每次成功发送后，调用侧提供可复制的 `tmux attach-session -t <session>` 入口。任务完成先展示“Claude 完整回复”或“Codex 完整回复”，再展示“调用侧结论”，最后重复 attach 入口。

完整回复保留可见内容顺序、文件/行号及全部风险项，排除隐藏思考和中间工具日志。capture 不完整时扩大历史并依目标规则取证。**Codex 当前只读取锁定 pane 的可见内容，没有原生 session ID/transcript 回退能力**；无法取得全文会报告限制，不把摘要冒充完整结果。CLI 手动重启或切换会话后停止信任原身份及历史。

## 授权与恢复

- 咨询/评审默认只读；写入及外部操作遵守用户授权。CLI 的工具权限设置不扩大任务范围。
- 发送前核验目标进程、managed 标记、项目根、权限契约及 pane 归属。旧 Claude 会话多 pane 无法确定时拒绝猜选。
- 复用或锁定会话时拒绝 dead pane；已知 target 仍可 capture/status 查看退出信息。attach/destroy 先解析并检查非空 session ID，目标消失时失败，不回退到其它会话。
- 忙碌或确认界面不注入消息，不自动输入 y；显示精确 target 和可见提示交用户处理。超时不重发。
- Helper 返回拒绝接管错误时停止，报告完整错误，不通过销毁重建绕过。
- 新建会话会短暂检查 pane 存活；CLI 立即退出或初始化失败时返回含 agent/session 的 `failed to start` 错误，不报告 started、不自动重试或销毁。存活检查不代表登录完成或输入就绪，仍需先 capture。
- 不传递密钥、Token、Cookie、完整环境变量等无关敏感信息。

Agent 仅在用户明确要求终止准确 session 时调用：

```bash
"$SKILL_DIR/scripts/tmux-agent.sh" "$AGENT" destroy "$SESSION"
```

裸 `tmux kill-session -t "$SESSION"` 仅供用户手工管理，Agent 不执行。任务完成和超时不自动销毁。

## 从 tmux-claude 迁移

2.0.0 将 Plugin 正式改名为 `tmux-agent`。通过原安装渠道移除旧 `tmux-claude` Plugin，再安装新 `tmux-agent`；Marketplace 的名称变化不保证自动替换。兼容 npm 安装同样选择新名称，并按原渠道移除旧 Skill，避免重复触发。迁移不需要销毁已有 tmux 会话。

- 保留 `tcc` 入口、Claude `tc-` 名称及 `@tmux_claude_*` metadata。
- 新 Plugin 内 `scripts/tmux-claude.sh` 是兼容包装，等价于 `scripts/tmux-agent.sh claude`。外部脚本仍需把旧安装目录路径改到新 Plugin，仓库不保留第二份 Plugin 源。
- 普通权限模式、UUID 缺失/非法等旧会话仍会拒绝 start/send，不静默升级；可 capture/status/attach，由用户决定是否重建。
- 旧版评测不代表 2.1.1 已通过动态门禁；需以新版本的验证结果为准。

## 依赖与扩展

依赖 Bash、tmux 3.2+ 和所选目标 CLI 及其正常登录状态。Claude 需支持其目标 reference 的启动参数，以及 uuidgen、Linux `/proc/sys/kernel/random/uuid`、Python 3 三者之一生成 UUID；Codex 不依赖 UUID 生成器。`name` / `format-name` 不启动 tmux，纯计算不要求安装 tmux。

本库保留 Claude Code 清单 `.claude-plugin/plugin.json` 与 Codex portable 清单 `plugin.json`，单 Skill 平铺在插件根目录。通过 `yj-skills` Marketplace 安装，或按 Agent 的 Skill 安装方式使用 `plugins/tmux-agent` 整目录；不需要 `skills/` 子目录。新增其它 CLI 参考 [适配器契约](references/adapters.md)。

确定性回归使用 Python 3.10+，例如 `python3.13 plugins/tmux-agent/tests/test_bridge.py` 与 `python3.13 plugins/tmux-agent/tests/test_app_bridge.py`。分别使用独立 tmux socket、临时 HOME、假 CLI/App Server/queue 和真实 Unix socket，不调用模型或用户会话；CLI 测试另需 tmux。本库平铺版已通过 CLI 23 项、App Helper 27 项；25 个行为用例位于 `evals/evals.json`，稳定附件位于仓库根 `evals-workspace/tmux-agent/fixtures/`。动态模型 eval 未运行。

## Claude App 试用验证

同步版本为 **2.1.1**。运行逻辑来自已审查提交；本库只适配平铺目录与公开分发信息。涉及 Claude Desktop 的三组仍待真实端到端验证，不能把隔离测试当作实测通过。请按 [Claude App 试用清单](references/claude-app-validation.md) 选择独立测试会话，并反馈每段投递与回信结果。
