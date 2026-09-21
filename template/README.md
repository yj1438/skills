# Example Plugin —— 双端插件完整模板

复制本目录作为新插件的起点：`cp -r template/ plugins/<你的插件名>/`。
本目录**不进 marketplace**，仅供复制参考。

## 组件清单

| 路径 | 作用 | Claude Code | Codex |
|------|------|:---:|:---:|
| `.claude-plugin/plugin.json` | Claude 插件清单 | ✅ | 忽略 |
| `plugin.json` | portable 插件清单（agent-plugins.org 标准） | 忽略 | ✅ |
| `skills/<name>/SKILL.md` | skill：模型按 description 决定何时用 | ✅ | ✅ |
| `skills/<name>/references/` | 第二层细节文档（渐进式披露） | ✅ | ✅ |
| `skills/<name>/scripts/` | 确定性脚本 | ✅ | ✅ |
| `commands/*.md` | 斜杠命令（固定流程快捷入口） | ✅ | — |
| `agents/*.md` | 子代理定义 | ✅ | — |
| `hooks/hooks.json` | 生命周期钩子（两端默认发现，一份共用，无需清单声明） | ✅ | ✅（需用户信任确认） |
| `mcp.json` | MCP 服务器，**一份文件两端共用**：Codex 原生发现；Claude 由清单 `"mcpServers": "./mcp.json"` 引用同一份 | ✅（引用） | ✅ |
| `scripts/` | hook/工具脚本 | ✅ | ✅ |
| `assets/` | portable 布局的标准目录（可为空） | 忽略 | ✅ |

## 复制后必改清单

1. 两份 `plugin.json`：改 `name`（kebab-case）、`version`、`description`
2. `skills/example-skill/`：目录名和 SKILL.md 的 `name` 改成你的 skill 名，重写 `description`
3. 用不到的组件**整文件/整目录删掉**（尤其 `mcp.json` 和 `hooks/`——留着会在安装时真的启动 MCP 服务器/钩子；同时记得删掉 `.claude-plugin/plugin.json` 里的 `"mcpServers"` 引用）
4. 在仓库根的两个 marketplace 文件里各加一条目

## 布局决策记录

- **生产插件（本仓库 `plugins/` 下）采用平铺**：单 skill 插件把 `SKILL.md` 直接放在插件根目录。
  Claude Code 官方支持（"auto-loaded as a single-skill plugin"）；Codex 对插件目录递归发现
  SKILL.md（社区实测 ADR 记录），平铺同样可被发现。若 Codex 实测发现平铺装载失败，回退方案：
  `mkdir skills/<name>/ && git mv SKILL.md skills/<name>/`。
- **本模板演示嵌套布局**（`skills/<name>/SKILL.md`）：这是双方文档的标准写法，也是
  **多 skill 插件**的唯一选择。新插件如果确定只有一个 skill，可以学生产插件平铺。
- **毕业规则（本仓库约定）**：纯 skill 插件保持平铺；一旦需要新增 `hooks/`、`commands/`、
  `agents/`、MCP（`.mcp.json`/`mcp.json`）或第二个 skill，就把整个插件"毕业"成嵌套——
  skill 载荷（`SKILL.md` + `references/` + `scripts/` + `assets/`）整体挪进 `skills/<name>/`，
  插件机械层留在根目录。原因：平铺后 `scripts/` 等目录在"skill 脚本"和"hook 脚本"之间
  归属歧义，且平铺插件加第二个 skill 时根 `SKILL.md` 与 `skills/` 并存的行为文档未定义。
- **Codex 界面信息**写在 portable `plugin.json` 的 `extensions.com.openai.interface`；
  Claude 的显示名用 `.claude-plugin/plugin.json` 的 `displayName`。
- **MCP 一份文件两端共用（已实测 ✅）**：`mcp.json` 用 Codex portable 格式（顶层 `$schema`
  + 每条目 `type` 字段），Codex 原生发现；Claude 侧在 `.claude-plugin/plugin.json` 写
  `"mcpServers": "./mcp.json"` 路径引用同一份。实测 `claude mcp list` 显示 ✔ Connected：
  Claude 完全兼容 `$schema` 顶层键与 `type` 字段，`.mcp.json` 无需存在。注意方向性：
  Codex portable 规范**禁止**把 MCP 内联进 `plugin.json`（闭合 schema），所以只能走
  "文件共用"，不能反过来内联。
- **hooks 同理共用**：`hooks/hooks.json` 两端都默认发现，清单无需声明。

## 已验证项（Claude Code，本机实测）

- [x] marketplace 与全部插件 `claude plugin validate` 通过
- [x] 平铺单 skill 插件：`SKILL.md` 在插件根目录被正常发现（`plugin details` 可见）
- [x] `"mcpServers": "./mcp.json"` 引用 Codex 格式文件（含 `$schema`/`type`）→ `claude mcp list` ✔ Connected
- [x] 清单引用的 `hooks` 路径正常装载（SessionStart 钩子可见）
- [x] 根目录共存 portable `plugin.json`（含 `extensions.com.openai`）对 Claude 无副作用

## 待验证项（需安装 codex CLI 后实测）

- [ ] `codex plugin marketplace add yj1438/skills` 能否解析 `.agents/plugins/marketplace.json`
- [ ] `policy.authentication` 的枚举值（文档写"ON_INSTALL 或首次使用"，精确值待确认）
- [ ] 无 MCP 的纯 skill 插件是否可省略 `policy` / `mcp.json`
- [ ] 平铺布局：Codex 装载插件后能否发现插件根目录的 `SKILL.md`（失败则按上方回退方案改回嵌套）
- [ ] 共用 `mcp.json` 在 Codex 侧的原生装载
