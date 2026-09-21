# yj-skills

yinjie 的双端 Agent 插件集 —— 同一份内容，同时发布为 **Claude Code 插件** 与 **Codex 插件**（基于开放的 Agent Skills / Agent Plugins 标准）。

## 安装

### Claude Code

```
/plugin marketplace add yj1438/skills
/plugin install bilibili-restore@yj-skills
/plugin install html-slides@yj-skills
```

### Codex CLI

```
codex plugin marketplace add yj1438/skills
```

然后在 Codex 内 `/plugins` 浏览安装。

## 插件列表

| 插件 | 说明 |
|------|------|
| [bilibili-restore](plugins/bilibili-restore/) | 还原 bilibili 客户端离线缓存视频：合并 `video.m4s` + `audio.m4s` 为 MP4，支持 `--output` 归集、`--index` 清单 |
| [html-slides](plugins/html-slides/) | 把 URL/文件/粘贴文本提炼成叙事弧线，渲染为单文件 HTML 演示文稿（4 种视觉预设、支持双语） |

## 仓库结构

```
├── .claude-plugin/
│   └── marketplace.json        # Claude marketplace（Claude 官方格式）
├── .agents/
│   └── plugins/
│       └── marketplace.json    # Codex marketplace（agent-plugins 格式）
├── plugins/
│   ├── bilibili-restore/       # 单 skill 插件：SKILL.md 平铺在插件根目录
│   │   ├── .claude-plugin/plugin.json   # Claude 清单
│   │   ├── plugin.json                  # Codex portable 清单
│   │   ├── SKILL.md
│   │   └── scripts/
│   └── html-slides/
│       ├── .claude-plugin/plugin.json
│       ├── plugin.json
│       ├── SKILL.md
│       └── references/
└── template/                    # 完整插件模板（不进 marketplace，复制用）
```

## 如何新增一个插件

1. `cp -r template/ plugins/<你的插件名>/`
2. 按模板 README 的"复制后必改清单"改两份 `plugin.json` 和 skill 内容
3. 在 `.claude-plugin/marketplace.json` 和 `.agents/plugins/marketplace.json` 各加一条目
4. `claude plugin validate .` 验证

## 设计要点

- **skill 内容（SKILL.md + 脚本 + 参考）只有一份**，两个工具共享——Agent Skills 已是开放标准（agentskills.io），Claude Code 与 Codex 均原生支持
- 每个插件维护**两份清单**（`.claude-plugin/plugin.json` 和根 `plugin.json`），各约 15 行，字段几乎相同，各端读各的
- 两个 marketplace 文件各自遵循本端文档规范；不尝试超集单文件，避免解析器兼容性赌博

## 验证状态

- [x] Claude Code：`claude plugin validate .` 通过
- [ ] Codex：按 [agent-plugins.org](https://agent-plugins.org) 与 OpenAI 官方文档编写，**待安装 codex CLI 后实测**（详见 `template/README.md` 待验证项）
