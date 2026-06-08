# Multi-Agent Orchestration Methodology

> 从生产实践提炼的通用多 Agent 编排方法论，适用于 Claude Code 的 Agent 工具。
> 核心目标：**用子 Agent 隔离上下文，用文件传递状态，用 resume 机制实现修正循环。**

---

## 1. 核心问题

单对话做复杂项目会失败，原因：
- 上下文窗口被历史填满，模型注意力衰减
- 实现和验收没有分离，自己给自己签收
- 修正迭代污染主上下文，几轮之后迷失方向
- 没有跨任务的记忆机制，同一个坑反复踩

**解法不是更大的窗口，而是更聪明的上下文管理。**

---

## 2. 模式总览

```
┌─────────────────────────────────────────────────────────┐
│  Orchestrator（主对话）                                   │
│  只调度，不干活。不读代码，不读报告，不编辑文件。              │
│                                                          │
│  职责：管理计划 → 派发子Agent → 收集结果 → 驱动修正循环     │
└──────────┬──────────────┬──────────────┬────────────────┘
           │              │              │
           ▼              ▼              ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐
    │  Planner   │ │    Dev     │ │  Tester    │
    │  规划+搭建  │ │  开发+修正  │ │  审查+验证  │
    └────────────┘ └────────────┘ └────────────┘
           │              │              │
           ▼              ▼              ▼
    ┌─────────────────────────────────────────────┐
    │           文件系统（唯一的状态源）               │
    │  dev-plan.md / design-guide.md               │
    │  lessons-learned.md / test-reports/*.md      │
    └─────────────────────────────────────────────┘
```

**三条铁律**：

| 铁律 | 含义 |
|------|------|
| 文件即记忆 | 子 Agent 的产出必须持久化到文件，不依赖内存 |
| 隔离即常态 | 每个子 Agent 只看到 Orchestrator 给它的信息 |
| 编排者不干活 | Orchestrator 不读产出内容，只接收路径和 PASS/FAIL |

---

## 3. 三个 Agent 角色

### 3.1 Planner（规划）

**什么时候用**：项目启动时运行一次。

**输入**：需求文档路径、约束条件、项目范围。

**输出**：
- `dev-plan.md` — 任务清单（含状态：⏳ 待办 / 🔄 进行中 / ✅ 完成 / ⚠️ 低质量通过）
- `design-guide.md` — 每个任务的设计指引（做什么、优先级、验收标准）
- 项目脚手架（目录结构、配置文件、公共代码）
- `lessons-learned.md` — 经验库初始文件（空模板）

**生命周期**：创建一次，不 resume。

**工具权限**：Read, Write, Edit, Bash, Glob, Grep

### 3.2 Dev（开发）

**什么时候用**：每个任务的开发阶段。

**输入**（由 Orchestrator 通过 prompt 传入）：
- 任务描述（编号 + 标题）
- dev-plan.md 路径
- design-guide.md 路径
- lessons-learned.md 路径
- 已有代码路径

**输出**：
- 代码文件（新建或修改）
- lessons-learned.md 更新（修正模式下）

**生命周期**：
- **新任务 → 新建 Agent**
- **修正轮次 → resume 同一个 Agent**（需要自己的开发上下文来理解测试反馈）

**工具权限**：Read, Write, Edit, Bash, Glob, Grep

### 3.3 Tester（测试）

**什么时候用**：每个任务的验收阶段。

**输入**：
- 任务描述
- 需求/设计指引路径
- 待测代码路径

**输出**：结构化测试报告，写入 `test-reports/` 目录。

**生命周期**：
- **新任务 → 新建 Agent**
- **重测轮次 → resume 同一个 Agent**

**工具权限**：Read, Write（仅报告）, Glob, Grep
**禁止**：Edit（不能修改源代码）

**为什么 Tester 需要 Write 但不需要 Edit**：Write 用于创建测试报告文件，Edit 禁止是为了防止 Tester 修改源代码。

---

## 4. 信息流

```
Planner                    Dev                        Tester
   │                        │                           │
   │ writes                  │ reads                     │ reads
   ▼                        ▼                           ▼
dev-plan.md ────────────► Dev prompt ──────────────► Tester prompt
design-guide.md ───────► (必读)                      (必读)
lessons-learned.md ─────► (必读)
                         │                           │
                         │ writes                    │ writes
                         ▼                           ▼
                    source code              test-reports/*.md
                         │                           │
                         │                    ┌──────┴──────┐
                         │                    │  Orchestrator│
                         │                    │  只看判定结果 │
                         │                    └──────┬──────┘
                         │                           │
                         │  FAIL 时 resume ◄──────────┘
                         │  传入报告路径列表
                         ▼
                    修正代码 + 更新 lessons-learned
```

**关键原则**：Orchestrator 是中转站，不是消费者。它只传递路径，不读取内容。

---

## 5. Agent 生命周期：New vs Resume

这是最关键的设计决策。

### 规则

| 场景 | 操作 | 原因 |
|------|------|------|
| 新任务首次开发 | 新建 Agent | 干净上下文，专注当前任务 |
| 同任务修正轮次 | resume 同一 Agent | 保留开发上下文，理解测试反馈 |
| 同任务重测轮次 | resume 同一 Tester | 保留测试上下文，对比前后变化 |
| 新任务（即使同一批次） | 新建所有 Agent | 避免跨任务上下文干扰 |

### 为什么修正必须 resume 而不是新建

- 测试反馈需要结合开发时的上下文才能理解（"当时为什么这样写"）
- 新 Agent 要重新读所有代码、重新理解意图，浪费 token 且容易误判
- resume 让 Dev Agent 能"看到"自己之前写了什么、为什么这样写

### Agent ID 管理

**创建 Agent 后立即获取 ID**：

```bash
find ~/.claude/projects/ -name "agent-*.meta.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
```

从文件名提取裸 ID：`agent-abc123.meta.json` → `abc123`

**使用规则**：
- `resume` 参数填裸 ID，不带前缀后缀
- `resume` 必须指定 `subagent_type`，且与创建时一致
- 每个 Agent 完成任务后，其 ID 在下一任务中失效，必须重新创建

---

## 6. 上下文保护规则

Orchestrator 的上下文是最宝贵的资源。这些规则防止它膨胀：

| # | 规则 | 正确做法 | 错误做法 |
|---|------|---------|---------|
| 1 | 不读子 Agent 产出内容 | 只接收路径和 PASS/FAIL | Read 子 Agent 写的文件 |
| 2 | 不读测试报告全文 | Grep 提取 `### 判定：PASS/FAIL` | Read 完整测试报告 |
| 3 | 不直接编辑代码 | 委托给 Dev Agent | 用 Edit 修改源文件 |
| 4 | 子 Agent 返回要精简 | Agent 模板强制结构化输出 | 子 Agent 返回大段描述 |
| 5 | 后台通知简短确认 | 回复"已确认" | 复述通知内容 |

**子 Agent 输出格式约束**（写入 Agent 模板）：

Dev Agent 完成时只返回：
```
开发完成
{task_id} section 已追加到 {file_path}
```

Tester Agent 完成时只返回：
```
测试结果：PASS / FAIL
报告路径：{path}
```

**任何额外解释、总结、信息都会污染 Orchestrator 上下文。**

---

## 7. 修正循环协议

```
round = 0

while round < MAX_ROUNDS (默认 3):
  if 本批所有任务 PASS:
    break

  round += 1

  # 1. 收集所有 FAIL 的测试报告路径
  fail_reports = []

  # 2. resume Dev Agent，一次性修正所有问题
  Agent(
    resume: "{DEV_ID}",
    subagent_type: "harness-dev",
    prompt: "请读取以下测试报告并修正所有问题：\n{fail_reports}\n\n目标任务：{task_ids}\n修正完成后更新 lessons-learned.md。"
  )

  # 3. resume Tester Agent 重测
  Agent(
    resume: "{TESTER_ID}",
    subagent_type: "harness-tester",
    prompt: "开发者已修正，请重新审查。"
  )

# 循环结束
# 全部 PASS → dev-plan.md 标记 ✅
# 仍有 FAIL → dev-plan.md 标记 ⚠️（低质量通过）
```

**要点**：
- 修正时把所有 FAIL 报告路径一次性传给 Dev，不要逐个修
- 重测时 resume 同一个 Tester，让它对比前后变化
- 超过最大轮次强制通过，但标记为 ⚠️

---

## 8. 经验库（Lessons Learned）

`lessons-learned.md` 是跨 Agent 传递知识的唯一可靠通道。每个 Dev Agent 在修正后追加经验。

### 写入原则

| 原则 | 含义 | 反例 → 正例 |
|------|------|------------|
| 原理 > 数值 | 写"为什么错"不写"改了什么值" | "shimmer 用 rgba(217,119,87,0.12)" → "accent色卡片的微光应与边框色系一致" |
| 模式 > 页面 | 写"哪种模式容易犯这个错" | "page03的VS对比要对齐" → "双栏对比布局中，两栏应朝分隔线对齐" |
| 可迁移 > 可复制 | 去掉具体值后还能指导决策吗？ | "page14阶梯图CSS要通用" → "可复用组件应使用通用CSS class名" |

### 格式

```markdown
# 经验库

## 通用经验
- [date] {一条通用经验}

## 布局
- [date] {一条布局经验}

## 样式
- [date] {一条样式经验}
```

### 生命周期管理

- Dev Agent 在修正完成后追加
- 经验太多时，Orchestrator 应定期精简（保留高价值、通用的）
- 每条经验能帮下一个 Dev Agent 避免类似错误，就是好的粒度

---

## 9. 计划文件（dev-plan.md）

```markdown
# 开发计划

## 项目信息
- 需求文档：{path}
- 总任务数：{N}

## 任务清单

| # | 任务ID | 标题 | 状态 | Dev ID | Tester ID | 备注 |
|---|--------|------|------|--------|-----------|------|
| 0 | - | 项目脚手架 | ✅ | - | - | Planner 直接完成 |
| 1 | task01 | {标题} | ⏳ | - | - | |
| 2 | task02 | {标题} | ⏳ | - | - | |
| 3 | task03 | {标题} | ⏳ | - | - | |

## 当前进度
- 正在执行：task01
- 已完成：0/3
```

**管理规则**：
- 由 Orchestrator 维护，子 Agent 不修改
- 每个任务完成后立即更新状态
- 记录 Agent ID 用于 resume

---

## 10. 与现有 Harness Skill 的关系

本方法论是 harness skill 的**多 Agent 执行层**，不是替代。

| 维度 | Harness Skill | 本方法论 |
|------|--------------|---------|
| 关注点 | 产品思考、需求确认、方向对齐 | Agent 机制、上下文管理、修正循环 |
| 人类参与 | 必须确认方向后才能开发 | 可自主运行（Orchestrator 自动调度） |
| Agent 使用 | 概念描述（Planner/Generator/Evaluator） | 具体的 Agent() 调用、resume 模式 |
| 状态文件 | feature-list.json, sprint-contract, progress | dev-plan.md, lessons-learned.md, test-reports |
| 质量保证 | Evaluator 概念 | Tester + 结构化 PASS/FAIL + 修正循环 |
| 适用阶段 | 项目前期（规划、确认） | 项目执行期（开发、测试、迭代） |

**可以组合使用**：harness skill 管方向和规划，本方法论管执行和迭代。

---

## 11. 适用与不适用场景

**适用**：
- 可拆分为独立子任务的中大型项目
- 需要反复迭代验证的任务（UI 开发、数据处理、动画等）
- 需要严格质量把控的项目
- 多轮执行后容易迷失方向的复杂任务

**不适用**：
- 单文件小修复
- 任务间强耦合、无法独立验证
- 不需要迭代修正的简单任务

---

## 12. 批量处理（可选）

当任务较多且彼此独立时，可以批量处理：

- 每批 N 个任务（默认 N=1，用户可指定）
- 每批启动 1 个 Dev Agent 连续开发
- 每批启动 Tester Agent 并行测试（可以是多个维度的 Tester）
- 修正循环按批执行

**并发规则**：
- Dev 阶段每批只有 1 个 Agent（串行开发保证一致性）
- Test 阶段可以有多个 Agent 并行（不同维度/不同任务）
- 无论批量大小，修正循环始终 resume 同一个 Dev Agent

---

## 13. 提议的通用 Agent 模板

基于以上方法论，提议三个通用 Agent：

### harness-planner

```yaml
---
name: harness-planner
description: |
  项目规划与脚手架搭建。阅读需求文档，制定开发计划和设计指南，
  创建项目基础结构和经验库。
  触发场景：项目启动、需要制定开发计划时。
tools: Read, Write, Edit, Bash, Glob, Grep
model: inherit
permissionMode: acceptEdits
---
```

职责：读需求 → 拆任务 → 写 dev-plan.md → 写 design-guide.md → 搭脚手架 → 初始化 lessons-learned.md

### harness-dev

```yaml
---
name: harness-dev
description: |
  任务开发与修正。按计划实现单个任务，或根据测试反馈修正问题。
  触发场景：开发新任务、修正测试反馈。
tools: Read, Write, Edit, Bash, Glob, Grep
model: inherit
permissionMode: acceptEdits
---
```

职责：读 plan + guide + lessons → 开发 → 自验 → 输出。修正模式下：读报告 → 修代码 → 更新 lessons

### harness-tester

```yaml
---
name: harness-tester
description: |
  任务审查与验证。审查实现是否符合需求，输出结构化 PASS/FAIL 报告。
  触发场景：开发完成后需要质量验证。
tools: Read, Write, Glob, Grep
model: inherit
permissionMode: acceptEdits
---
```

职责：读 plan + guide + 代码 → 审查 → 写报告（PASS/FAIL + 问题列表）。重测模式下只验证上次 FAIL 项。

**关键约束**：Tester 没有 Edit 权限，不能修改源代码。只能 Write 到 test-reports/ 目录。

---

## 14. 日志

Orchestrator 维护 `main-log.md`，记录每个关键步骤：

```markdown
- {yymmdd hhmm} 项目启动，需求：{path}
- {yymmdd hhmm} 计划完成：{N}个任务
- {yymmdd hhmm} 开始 task01：{标题}
- {yymmdd hhmm} 开发完成 (DEV_ID: {id})
- {yymmdd hhmm} 测试结果：PASS
- {yymmdd hhmm} task01 完成
- ...
- {yymmdd hhmm} 项目完成，迭代统计：1次通过{X}个 / 2次通过{Y}个 / 强制通过{Z}个
```

---

*灵感来源：Meta-Harness (Khattab & Finn, 2026)、Anthropic Harness Engineering 实践*
