---
name: harness
description: 面向 Claude Code 的 Web 开发执行 Harness。用户要为中大型 Web/全栈项目建立“规划→单 feature 实现→独立验收→状态落盘”的长期工作流，或提到 harness、sprint contract、feature list、Evaluator、分轮迭代、AI 容易跑偏/假完成时，务必使用此 skill。尤其适合需要 docs/harness 持久化状态、强制用户确认需求、用测试和独立验收防止一次性写完的场景。
---

# Web Development Harness

> 面向 Claude Code 的 web 应用长期迭代执行框架。
>
> 核心目标：**把需求确认、增量实现、独立验收、项目状态追踪拆开，避免 AI 一口气写完整个项目后失控。**

灵感来源：[How we designed Claude's harness for long-running tasks](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## 这个 skill 解决什么问题

当用户要做的是一个会持续多轮的 web 项目，而不是一次性小改动时，Claude 很容易出现这些问题：

- 需求没对齐就开始写代码
- 一次改太多文件，回滚困难
- 说“做完了”，但没有真正验收
- 依赖对话历史传递状态，过几轮就迷路
- 多 agent 并行时互相踩文件

这个 skill 的作用，就是把工作流强制变成：

1. **先澄清并确认方向**
2. **把需求写入仓库文件**
3. **一次只做一个 feature**
4. **实现和验收分离**
5. **每轮把结果写回 `docs/harness/`**

## 何时使用

遇到下面任一情况，就应该使用这个 skill：

- 用户说要“搭一个完整项目 / 从零做一个 web app / 全栈应用”
- 用户希望 Claude **分阶段**推进，而不是一次生成全部代码
- 用户提到要有 `feature list`、`sprint`、`milestone`、`验收`、`评估`
- 用户担心 AI 跑偏、乱改、假完成、上下文溢出
- 用户明确提到 `harness`、`Planner`、`Evaluator`、`Sprint Contract`
- 需要多人或多 agent 协作，且必须靠文件维护状态

不适合的场景：

- 单文件小修复
- 很明确的单个功能改动
- 不需要跨多轮追踪状态的任务

## 核心原则

### 1. 生成与评估分离
实现 feature 的 agent 不负责给自己签收。验收应由当前对话中的 Claude 亲自完成，或由单独 agent 完成。

### 2. 仓库文件才是状态源
不要依赖“前文说过什么”。项目状态必须落到文件中。

### 3. 一次只推进一个 feature
如果一次实现多个 feature，失败时很难判断是哪一步出问题，也会让验收失焦。

### 4. 先确认方向，再进入开发
在用户明确确认产品方向之前，不要生成最终 feature list，更不要开始写代码。

### 5. 优先使用 Claude Code 原生能力
用 Claude Code 的 Read / Edit / Write / Grep / Glob / Bash / Agent / Task 工具完成工作，不要写成其他平台专属语法。

---

## 推荐的仓库内文件结构

如果仓库里还没有 harness 文件，优先创建或补齐下面这些文件：

```text
docs/
  specs/
    product-spec.md
  harness/
    feature-list.json
    sprint-contract.md
    progress.md
    evaluation-reports/
```

如果这个 skill 自己的模板文件存在，可以把它们作为参考或复制来源：

- `docs/specs/product-spec.template.md`
- `docs/harness/feature-list.template.json`
- `docs/harness/sprint-contract.template.md`
- `docs/harness/progress.template.md`
- `docs/harness/evaluation-report.template.md`

## 你在 Claude Code 里应该怎么执行

### 0. 先判断是不是该进 harness 模式
如果用户只是要一个小功能或修一个 bug，不要强行套 harness。

只有在任务明显属于长期、多轮、易跑偏的 web 项目时，才采用这套流程。

### 1. Planner 阶段：先把方向讲清楚
当用户只给了 1-4 句需求时：

1. 先澄清目标用户、核心流程、P0 功能、技术栈约束
2. 起草 `docs/specs/product-spec.md`
3. 给用户一个**结构化摘要**，等待明确确认
4. 用户确认后，再生成 `docs/harness/feature-list.json`
5. 初始化 `docs/harness/progress.md`

给用户确认时，用这个格式即可：

```text
产品定位: <一句话>
核心功能(P0):
- ...
- ...

技术选型:
- 前端: ...
- 后端: ...

视觉/交互方向:
- ...

预计 feature 数量: <N>
预计 sprint 轮次: <M>

请确认以上方向，或直接指出要改的地方。
```

### Planner 阶段硬规则

- 不要在用户确认前开始开发
- 不要在用户确认前生成最终版 feature list
- feature 必须是“用户可感知”的最小交付单元
- 每个 feature 必须有可执行的验收步骤
- 优先级顺序固定为：**P0 → P1 → P2**

---

## 2. Generator 阶段：一次只做一个 feature

开始实现前，先读状态：

1. 当前仓库状态
2. `docs/harness/progress.md`
3. `docs/harness/feature-list.json`
4. 当前是否已有未完成的 `sprint-contract.md`

然后执行下面的循环。

### 单 feature 循环

#### Step 1. 选择本轮 feature
选取优先级最高且尚未通过的 feature。

#### Step 2. 写 Sprint Contract
更新或创建 `docs/harness/sprint-contract.md`，至少写清：

- 本轮只做哪个 feature
- 涉及哪些文件或目录
- 验收标准
- 需要跑哪些测试
- 明确不做什么

然后把 Sprint Contract 摘要发给用户，必要时等待确认。对于高不确定性任务，优先使用计划模式获得确认。

#### Step 3. 先写失败测试（如果适合 TDD）
如果功能边界明确，就先补测试，让测试先失败。

常见测试包括：
- 单元测试
- 组件测试
- 集成测试
- Playwright / E2E

如果任务不适合严格 TDD，也至少先写验收条件，不要裸写实现。

#### Step 4. 实现直到通过
只改与当前 feature 直接相关的代码。

每完成一个明确小步后，优先运行项目已有校验命令，例如：

```bash
npm run type-check
npm run lint
npm run test
```

如果项目没有这些命令，先读 `package.json` 或现有脚本，按真实项目情况执行，不要假设命令一定存在。

#### Step 5. 独立验收
实现完成后，不要只看代码。必须根据 Sprint Contract 验收：

- 功能是否真的可用
- 测试是否通过
- 是否存在明显 UI stub / 假逻辑
- 是否满足关键交互路径

把结果写入 `docs/harness/evaluation-reports/` 下的新报告。

#### Step 6. 更新状态文件
验收通过后，再更新：

- `docs/harness/feature-list.json` 中对应 feature 的 `passes`
- `completion_status`
- `docs/harness/progress.md`

如果未通过：
- 不要把 feature 标记为完成
- 把失败原因和后续动作写回 progress / evaluation report

---

## 3. Evaluator 阶段：如何验收

Evaluator 的职责不是“说看起来不错”，而是判断这个 feature 能不能进入下一轮。

### 最低验收维度

1. **功能完整性**
   - 是否覆盖 Sprint Contract 的范围
   - 是否存在只做 UI、没有真实逻辑的 stub
   - 核心路径是否真实可跑通

2. **代码质量**
   - 是否符合当前仓库架构
   - 是否引入明显重复或不必要复杂度
   - 是否通过类型/lint/测试校验

3. **可用性**
   - 用户是否能在不靠解释的情况下完成核心操作
   - 是否有基本的 loading / error / success 反馈

4. **设计一致性**
   - UI 是否和现有产品风格一致
   - 是否明显是拼凑模板

### Evaluator 输出要求

必须输出：

- PASS / FAIL
- 发现的问题
- 可以直接执行的修复建议
- 使用过的证据（测试结果、截图、日志、手动验证结论）

禁止只写：

- “整体不错”
- “建议优化一下体验”
- “可以继续”

这种话没有执行价值。

---

## 4. 多 agent 并行模式

只有在以下条件同时满足时，才考虑并行：

- feature 数量较多
- 模块边界清晰
- 共享文件较少
- 用户明确希望并行推进

并行时要先定义：

- 模块所有权
- 共享文件
- 接口契约
- 合并顺序

可使用如下文件：

- `docs/harness/module-map.json`
- `docs/harness/interface-contracts.md`
- `docs/harness/interface-change-requests.md`

### 并行硬规则

- 每个 agent 只改自己负责范围内的文件
- 共享接口先冻结，再并行开发
- 合并必须串行，不能大家一起往主分支堆
- 若用户没有明确要求，不主动进入多 agent 模式

---

## 五条常见防线

### 防线 1：方向跑偏
**现象**：AI 自己补需求，做成另一个产品。

**做法**：先出 spec 摘要，必须让用户确认。

### 防线 2：虚假完工
**现象**：代码写了，但功能实际不可用。

**做法**：必须按 Sprint Contract 验收，不以“代码已写完”作为完成标准。

### 防线 3：上下文溢出
**现象**：多轮后 Claude 忘了为什么这么做。

**做法**：把状态写进 `docs/harness/`，新上下文先读文件。

### 防线 4：一次改太多
**现象**：改动很大，失败后难以定位。

**做法**：一次只推进一个 feature。

### 防线 5：自评估放水
**现象**：实现者对自己的结果过于宽松。

**做法**：验收与实现分离，至少在流程上分成两个明确阶段。

---

## 推荐输出文件

### `docs/harness/feature-list.json`
至少包含：

- `id`
- `priority`
- `title`
- `description`
- `passes`
- `acceptance_criteria`
- `e2e_test_steps`
- `dependencies`

### `docs/harness/progress.md`
至少记录：

- 当前轮次
- 正在处理的 feature
- 上一轮完成内容
- 已知阻塞问题
- 下一轮计划

### `docs/harness/evaluation-reports/*.md`
至少记录：

- 本轮 feature / sprint
- 测试结果
- PASS / FAIL
- 问题列表
- 后续建议

---

## 执行时的语气与行为要求

- 要像项目负责人一样控节奏，而不是像代码生成器一样一路冲到底
- 用户未确认方向前，不要抢跑
- 不要为了“显得快”而跳过验收
- 不要把并行、多分支、重型流程强加给简单任务
- 如果仓库已有成熟流程，优先贴合现有流程，而不是强推模板

## 一个最小使用范式

当用户说：

> “帮我从零做一个中后台 web 系统，但别一口气写完，按 feature 一轮一轮推进。”

你应该这样做：

1. 进入 harness 模式
2. 澄清需求并起草 spec
3. 给用户确认摘要
4. 生成 feature list 和 progress
5. 只选择一个 P0 feature
6. 写 sprint contract
7. 实现、测试、验收
8. 更新状态文件
9. 再进入下一轮

而不是：

- 直接生成完整项目代码
- 一次做完所有页面和接口
- 没有任何中间状态文件
- 没有明确验收就宣布完成

## 参考文件

如果需要更细的模板或规范，继续读取：

- `AGENTS.md`
- `ARCHITECTURE.md`
- `docs/specs/product-spec.template.md`
- `docs/harness/feature-list.template.json`
- `docs/harness/sprint-contract.template.md`
- `docs/harness/progress.template.md`
- `docs/harness/evaluation-report.template.md`

优先把这些文件当模板使用，而不是机械照抄。