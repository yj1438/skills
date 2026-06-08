---
name: multi-agent-orchestrator
description: |
  多Agent编排执行框架。将复杂需求拆分为子任务，通过 Planner/Dev/Tester 三个专用Agent
  协同完成计划、开发、测试、修正的完整迭代循环。当你面对中大型项目、需要分步推进的
  复杂任务、或多轮迭代容易让上下文失控的场景时，使用此skill。即使项目看起来不大，
  只要涉及"多个独立功能需要逐个开发和验收"，就应该启用此模式。
  与 harness skill 的关系：harness 管产品方向和需求确认，本 skill 管执行编排。
  可以先用 harness 确认方向，再用本 skill 执行；也可以单独使用。
  不适用：单文件修复、明确的小改动、不需要迭代验证的任务。
---

# Multi-Agent Orchestrator

> 你是编排者（Orchestrator）。你的唯一职责是调度——你**不开发、不测试、不编辑任何代码文件**。
> 所有具体工作通过三个专用子 Agent 完成：Planner（规划）、Dev（开发）、Tester（测试）。

## 前置条件

确认 `.claude/agents/` 下存在三个 Agent 模板：
- `harness-planner` — 规划与脚手架
- `harness-dev` — 开发与修正
- `harness-tester` — 审查与验证

## 铁律

这些规则保护你的上下文不被污染。违反任何一条都会导致多轮迭代后迷失方向：

1. **不碰代码** — 绝对不直接编辑任何源代码文件，所有修改委托给 harness-dev
2. **不读产出** — 绝对不读取子 Agent 的产出文件内容，只接收它返回的路径和 PASS/FAIL 判定
3. **不读报告** — 绝对不读取测试报告全文，只用 Grep 提取判定行
4. **记日志** — 每个关键步骤追加到 main-log.md
5. **报进度** — 每完成一个任务向用户报告

---

## 执行流程

### Phase 1：初始化

1. 理解用户的项目意图。用户可能提供：
   - 一个需求文档路径（直接使用）
   - 口头描述（先整理成文档，再进入后续流程）
2. 确认**输出目录**（默认为需求文档所在目录或当前项目根目录）
3. 如果项目方向不明确，先和用户对齐核心目标和范围，再继续
4. 创建日志文件 `{OUTPUT_DIR}/main-log.md`，写入：

```
- {yymmdd hhmm} 项目启动
- {yymmdd hhmm} 需求来源：{文档路径 / 口头描述}
- {yymmdd hhmm} 输出目录：{OUTPUT_DIR}
```

### Phase 2：计划

启动 harness-planner 子 Agent，传入需求文档路径和输出目录。Planner 会产出 dev-plan.md（任务清单）、design-guide.md（设计指引）和项目脚手架。

等待 Planner 完成后，记录它返回的文件路径到日志。

日志：
```
- {yymmdd hhmm} 计划完成：{N}个任务
- {yymmdd hhmm} dev-plan: {path}
- {yymmdd hhmm} design-guide: {path}
```

### Phase 3：逐任务循环

读取 dev-plan.md，找到所有 ⏳ 待办任务，按顺序逐个执行以下步骤。

#### 3.1 开发

启动 harness-dev 子 Agent，prompt 中传入：
- 任务编号和标题（从 dev-plan.md 获取）
- dev-plan.md、design-guide.md、lessons-learned.md 的路径
- 项目已有代码的路径

等待完成。**完成后立即获取 Agent ID**（见"Agent ID 管理"章节），记为 `DEV_ID`。

日志：`- {yymmdd hhmm} {task_id} 开发完成 (DEV_ID: {DEV_ID})`

#### 3.2 测试

启动 harness-tester 子 Agent（可用 `run_in_background: true` 提高并行度），prompt 中传入：
- 任务编号和标题
- 待测代码路径
- design-guide.md 路径
- 输出目录

等待完成，获取 Agent ID 记为 `TESTER_ID`。

然后用 Grep 提取判定结果，**不要 Read 完整报告**：

```
Grep(pattern="### 判定", path="{OUTPUT_DIR}/test-reports/{task_id}.md")
```

日志：`- {yymmdd hhmm} {task_id} 测试结果：{PASS/FAIL} (TESTER_ID: {TESTER_ID})`

#### 3.3 判定

- **PASS** → 更新 dev-plan.md 状态为 ✅，向用户报告进度，进入下一个任务
- **FAIL** → 进入修正循环

#### 3.4 修正循环

修正最多进行 3 轮。每轮的步骤：

1. 用 Grep 从测试报告中找到 FAIL 的报告路径
2. resume harness-dev（使用 `DEV_ID`），prompt 中传入所有 FAIL 报告的路径和目标任务 ID。Dev Agent 会读取报告、修正代码、更新 lessons-learned.md
3. resume harness-tester（使用 `TESTER_ID`），prompt 告知开发者已修正，请重新审查
4. 再次用 Grep 提取判定结果
5. 如果 PASS，退出循环；如果仍然 FAIL，继续下一轮

循环结束后更新 dev-plan.md：全部 PASS 标记 ✅，3 轮后仍 FAIL 标记 ⚠️（低质量通过）。

日志：
```
- {yymmdd hhmm} {task_id} 第{round}轮修正 (DEV_ID: {DEV_ID})
- {yymmdd hhmm} {task_id} 第{round}轮重测：{PASS/FAIL}
```

#### 3.5 报告用户

每个任务完成后告诉用户：`{task_id} ({标题}) 完成（{已完成}/{总数}），迭代{N}次`

### Phase 4：收尾

全部任务完成后，写入最终统计到日志：

```
- {yymmdd hhmm} ──── 项目完成 ────
- {yymmdd hhmm} 全部 {N} 个任务完成
- {yymmdd hhmm} 迭代统计：1次通过{X}个 / 2次通过{Y}个 / 3次通过{Z}个 / 强制通过{W}个
```

向用户报告完成。

---

## Agent ID 管理

子 Agent 完成后需要获取其 ID，以便后续 resume。获取方式：

```bash
find ~/.claude/projects/ -name "agent-*.meta.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
```

从文件名提取裸 ID：`agent-abc123.meta.json` → `abc123`

使用规则：
- resume 时填裸 ID，不带 `agent-` 前缀和 `.meta.json` 后缀
- resume 时必须指定 `subagent_type`，且与创建时一致
- 同一任务的修正/重测循环中复用同一个 ID
- 不同任务必须重新创建子 Agent，旧 ID 失效
- 如果获取不到 ID，暂停并报告错误，不要跳过

---

## 上下文保护速查

| 场景 | 正确做法 | 错误做法 |
|------|---------|---------|
| 子 Agent 返回结果 | 只看路径和 PASS/FAIL | Read 它写的文件 |
| 判定测试结果 | Grep 提取 `### 判定` 行 | Read 完整报告 |
| 代码需要修改 | 委托给 harness-dev | 自己用 Edit 改 |
| 后台 Agent 通知到达 | 回复"已确认" | 复述通知内容 |

---

## 批量模式

当任务较多且彼此独立时，可以每批处理 N 个任务（默认 N=1，用户可指定）。

- 每批启动 1 个 Dev Agent 连续开发本批所有任务
- 每批启动 Tester Agent 测试本批所有任务
- 修正循环按批执行：收集本批所有 FAIL → resume Dev 一次修正 → resume Tester 重测

日志格式：
```
- {yymmdd hhmm} ── Batch 1: task01-03 ──
- {yymmdd hhmm} 本批开发完成 (DEV_ID: {id})
- {yymmdd hhmm} task01 测试：PASS
- {yymmdd hhmm} task02 测试：FAIL
- {yymmdd hhmm} 第1轮修正：task02 (DEV_ID: {id})
- {yymmdd hhmm} 第1轮重测 task02：PASS
- {yymmdd hhmm} Batch 1 完成
```

---

## 与 harness skill 的关系

| 维度 | harness skill | 本 skill |
|------|--------------|---------|
| 关注点 | 产品方向、需求确认、用户对齐 | Agent 调度、迭代执行、上下文管理 |
| 人类参与 | 必须确认方向后才能开发 | 可自主运行（但方向不明确时会先对齐） |
| 使用时机 | 项目初期，确定做什么 | 确定做什么之后，规划怎么做和执行 |

典型组合：先用 harness 确认产品方向和 feature list → 再用本 skill 执行开发和迭代。
也可以单独使用本 skill，它会在方向不明确时主动与用户对齐。
