# harness

> 面向 Claude Code 的 web 项目执行框架：把规划、实现、验收和状态追踪拆开，适合多轮迭代的中大型 Web / 全栈项目。

## 适用场景

推荐在以下场景使用：

- 从零搭建一个完整 web 应用
- 需要按 feature 一轮一轮推进
- 需要让用户先确认产品方向，再开始开发
- 需要把项目状态持续写回仓库文件
- 需要把“实现”和“验收”拆开，降低假完成风险

不推荐：

- 小修小补
- 单文件改动
- 一次性即可完成的简单页面

## 核心流程

```text
需求澄清 → spec 草稿 → 用户确认 → feature list → 单 feature sprint → 独立验收 → 更新状态 → 下一轮
```

## 仓库内状态文件

通常落在：

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

模板文件已随 skill 提供：

- `docs/specs/product-spec.template.md`
- `docs/harness/feature-list.template.json`
- `docs/harness/sprint-contract.template.md`
- `docs/harness/progress.template.md`
- `docs/harness/evaluation-report.template.md`

## Claude Code 适配说明

这个 skill 已按 Claude Code 使用方式重写：

- 使用 Claude Code 原生工具和 agent，而不是 `use_skill(...)`
- 以仓库内文件为状态源，而不是依赖其他平台路径
- 不假设必须直接合并 `main`
- 强调按真实项目脚本跑测试，而不是写死某个平台工作流

## 支撑文档

- `SKILL.md`：主工作流与触发说明
- `AGENTS.md`：Planner / Generator / Evaluator 的职责拆分
- `ARCHITECTURE.md`：推荐架构和代码约束
- `scripts/`：初始化、校验、评估辅助脚本

## 灵感来源

- [How we designed Claude's harness for long-running tasks](https://www.anthropic.com/engineering/harness-design-long-running-apps)
