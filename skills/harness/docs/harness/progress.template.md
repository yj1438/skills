# Progress Tracking

> 项目全局进度跟踪，跨轮次上下文传递的核心载体。每轮开发完成后必须更新。

## 项目概览

| 字段 | 值 |
|------|-----|
| 项目名 | Project Name |
| 开始日期 | YYYY-MM-DD |
| 当前状态 | 开发中 / 待验收 / 完成 |
| 总预估时间 | X 小时 |
| 已耗时 | Y 小时 |
| 完成度 | Z% |

---

## 当前轮次信息

| 字段 | 值 |
|------|-----|
| 轮次 ID | round-1 / round-2 / ... |
| 开发 Feature | feat-001 (Feature Name) |
| Sprint Contract | docs/harness/sprint-001.md |
| 开始时间 | YYYY-MM-DD HH:MM |
| 预计完成 | YYYY-MM-DD HH:MM |
| 当前状态 | 进行中 / 待评估 / 完成 |

---

## 上一轮次总结 (可选)

### 完成情况

- [x] feat-001: User Authentication
  - 完成时间: 2026-03-31 15:00
  - Evaluator 评分: 8.5/10
  - 备注: 交互反馈需优化

- [x] feat-002: Todo List Display
  - 完成时间: 2026-03-31 16:00
  - Evaluator 评分: 9.0/10
  - 备注: 质量优秀

### 遇到的问题

| 问题 | 根因分析 | 解决方案 | 状态 |
|------|---------|---------|------|
| 问题 1 描述 | 根因 | 解决方法 | 已解决/进行中 |

### 已知技术债务

- [ ] 性能优化: API 响应时间待改进
- [ ] 代码重构: TodoItem 组件复杂度过高
- [ ] 文档补充: 国际化逻辑文档缺失

---

## 待处理事项 (Backlog)

### 本轮计划

```
当前轮次要做的事情:
1. [优先级] Feature Name
2. [优先级] Feature Name
```

### 后续计划

```
下一轮预计:
1. [优先级] Feature Name
2. [优先级] Feature Name
```

---

## Git 提交历史 (近 5 次)

```
commit abc1234 - feat: Add user authentication
Author: Generator Agent <agent@harness>
Date:   2026-03-31 15:30

  - Implement JWT token validation
  - Add login form UI
  - Tests: 95% coverage

commit def5678 - feat: Add todo list display
Author: Generator Agent <agent@harness>
Date:   2026-03-31 16:00

  - Fetch todos from API
  - Render with pagination
  - Tests: 88% coverage
  - Evaluator signed off: Pass ✓
```

---

## 代码质量指标

| 指标 | 目标 | 当前 | 趋势 |
|------|------|------|------|
| TypeScript 覆盖率 | 100% | 99% | ↑ |
| ESLint 错误 | 0 | 0 | ↔ |
| 测试覆盖率 | 80%+ | 82% | ↑ |
| Lighthouse Score | 90+ | 92 | ↑ |

---

## 常见问题排查

### Q1: 上一轮为什么没完成？

**A**: 列出阻塞原因和继续处理的方案

### Q2: 为什么这个 feature 被延期？

**A**: 列出评估结果和重新规划

---

## Agent 工作清单 (新轮次启动时)

开启新轮次前，Agent 必须执行：

- [ ] 执行 `pwd` 确认工作目录
- [ ] 执行 `git status` 确认当前分支无未提交变更
- [ ] 读取 `git log -10 --oneline` 确认最近工作
- [ ] 读取本文件了解项目状态
- [ ] 读取 `docs/harness/feature-list.json` 选择下一个优先级最高的未完成 feature
- [ ] 读取对应 feature 的详细要求
- [ ] 提出 Sprint Contract 与 Evaluator 评审

---

## 评估报告索引

- [Round 1 Evaluation](evaluation-reports/round-1-evaluation.md)
- [Round 2 Evaluation](evaluation-reports/round-2-evaluation.md)
- ...

---

## 变更日志

| 日期 | 变更内容 | 变更人 |
|------|---------|-------|
| 2026-03-31 | 初始化项目 | Planner Agent |
| 2026-03-31 | 完成 feat-001 | Generator Agent |
