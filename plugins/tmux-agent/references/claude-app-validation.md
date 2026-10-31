# Claude App Code 试用清单

版本：tmux-agent 2.1.1。**Claude App inbox 相关三组链路仍待真实端到端验证**；本清单供有 Claude Desktop 的人实测，不代表已通过。只测试本机 Code 会话，不覆盖普通聊天、Cowork、云端或 SSH 会话。

## 准备

- 本机有 Claude Desktop，并打开一个本地 Code 测试会话，命名为 `TEST_CLAUDE_APP`。
- 有 Codex App 时，另开一个 Code 测试会话，命名为 `TEST_CODEX_APP`。标题应唯一，避免重名。
- App Helper 需要 Python 3.10+；入口会选择已安装版本，也可设置 `TMUX_AGENT_PYTHON`。涉及 CLI 回信时需要 Bash、tmux 3.2+，且原 CLI 由 tmux-agent 管理。
- Codex CLI 需支持 `queue` 和 App Server 元信息协议；Claude Code 需提供本机 Desktop 登记与 peerProtocol=1 的 inbox。请记录实际 App/CLI 版本，不以版本号代替实测结果。

设置 `SKILL_DIR` 为安装后包含 SKILL.md 的插件目录，先只读列出会话：

```bash
SKILL_DIR="<tmux-agent 插件根目录>"
bash "$SKILL_DIR/scripts/tmux-agent.sh" claude-app list
bash "$SKILL_DIR/scripts/tmux-agent.sh" codex-app list --search "TEST_CODEX_APP"
```

确认列表里的标题、目录与测试会话一致。目标未明确或重名时先选择准确 ID；不要按最新时间猜选。Claude 列表为空时，记录版本、会话类型和错误后停止该项，不用 CLI 替代 App，也不猜 socket 路径或借用 token。

以下命令任一步失败就先停止；address 必须返回有效地址，不能把错误 JSON 继续当作回信地址。

## 1. Codex CLI → Claude App → 原 Codex CLI

在原受管 Codex CLI 的项目目录运行；CLI target 应来自 Helper 的 name/list/target 流程：

```bash
RETURN_TO=$(bash "$SKILL_DIR/scripts/tmux-agent.sh" codex address "<原 Codex session:window.pane>")
printf '%s\n' '通信测试：只计算 17+25，结果含 TEST_CLI_TO_CLAUDE_APP 与中文多行文本。允许读取本 Skill 和执行回信必需的 Helper 操作；不读取业务文件、不修改代码或配置。完成后向信封中的原地址回信一次。' |
  bash "$SKILL_DIR/scripts/tmux-agent.sh" claude-app send "TEST_CLAUDE_APP" --reply-to "$RETURN_TO"
```

检查：Claude App 是否确实收到该请求并处理；原 Codex pane 是否收到同一 request_id 的完整结果。回信 Agent 应先按原 pane_id 解析当前坐标，再 capture 确认空闲；实际空闲才使用 `--confirm-idle`。

## 2. Claude App → Codex App → 原 Claude App

从 Claude App 的上述本地 Code 测试会话发起，先取得准确的原会话地址：

```bash
RETURN_TO=$(bash "$SKILL_DIR/scripts/tmux-agent.sh" claude-app address "TEST_CLAUDE_APP")
printf '%s\n' '通信测试：只计算 17+25，结果含 TEST_CLAUDE_APP_TO_CODEX 与中文多行文本。允许读取本 Skill 和执行回信必需的 Helper 操作；不读取业务文件、不修改代码或配置。完成后向原 Claude App 回信一次。' |
  bash "$SKILL_DIR/scripts/tmux-agent.sh" codex-app send "TEST_CODEX_APP" --reply-to "$RETURN_TO" --open
```

`--open` 会在入队后打开准确 Codex 会话；不希望切换视图时可省略并手动打开同一目标。检查 Codex 是否处理该请求，以及原 Claude App inbox 是否收到同一编号的结果。

## 3. Codex App → Claude App → 原 Codex App

从 Codex App 的上述测试会话发起：

```bash
RETURN_TO=$(bash "$SKILL_DIR/scripts/tmux-agent.sh" codex-app address "TEST_CODEX_APP")
printf '%s\n' '通信测试：只计算 17+25，结果含 TEST_CODEX_APP_TO_CLAUDE 与中文多行文本。允许读取本 Skill 和执行回信必需的 Helper 操作；不读取业务文件、不修改代码或配置。完成后向原 Codex App 回信一次。' |
  bash "$SKILL_DIR/scripts/tmux-agent.sh" claude-app send "TEST_CLAUDE_APP" --reply-to "$RETURN_TO"
```

检查 Claude 是否处理该请求，以及原 Codex thread 是否收到 kind=result、相同 request_id 的结果。接收结果后只呈现内容，不继续回信或启动新委派。

## 判定与反馈

每组单独记录以下状态；只有最后一项符合才算该组往返通过：

1. Helper 返回 queued 或 submitted，只证明入队/写入，**不能算完成**。
2. 目标会话可见实际请求，或接收方明确报告 held/refused/pending。
3. 原发送会话收到相同 request_id 的一次完整结果，内容为 42，中文与多行保留，无循环互聊。

遇到 unknown、超时或异常回执不要重发。held/refused 如实记录，不更改权限绕过。结果只到了一边，应标为“单向送达，回信未确认”。

反馈模板：

```text
系统/架构：
tmux-agent：2.1.1
Claude Desktop / 内嵌 Claude Code 版本：
Claude CLI / Codex App / Codex CLI 版本：
Python / tmux 版本：
测试组：1 / 2 / 3
request_id：
投递回执 status：
目标是否可见请求：
接收方是否 held/refused/pending：
原发送方是否收到一次完整结果：
实际错误与预期差异：
```

只提供本次测试所需输出；不要附 token、cookie、完整环境变量或无关聊天历史，目录可脱敏。
