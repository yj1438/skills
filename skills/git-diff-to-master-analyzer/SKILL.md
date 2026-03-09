---
name: git-diff-to-master-analyzer
description: 分析当前分支与 master 分支的代码差异，生成变更概览、功能总结和代码审查建议。当用户提到 diff 分析、分析变更、总结迭代、和 master 有什么不同、PR 描述、变更总结时使用。
---

# Git Diff To Master 分析器

这个 Skill 用于分析当前分支与 master 分支的代码差异，生成完整的分析报告。

## 功能特性

- 自动检测当前分支与 master 的差异
- 智能过滤噪音文件（node_modules、dist、lock、.min.js 等）
- 变更概览统计（文件数量、类型分类）
- 功能总结（基于 commit、和 target branch (默认是 master) diff 内容，综合整个项目代码，进行分析）
- 代码审查建议（潜在问题、优化点）
- 变更文件清单
- 可选生成 PR 描述

## 执行步骤

### 1. 获取分支信息

首先获取当前分支和基本信息：

```bash
# 获取当前分支名
git branch --show-current

# 获取与 master 的分叉点
git merge-base master HEAD

# 获取差异 commit 列表
git log master..HEAD --oneline
```

### 2. 获取变更统计

```bash
# 获取变更文件统计（排除噪音）
git diff master --stat -- \
  ':(exclude)*node_modules*' \
  ':(exclude)*dist*' \
  ':(exclude)*.lock' \
  ':(exclude)*package-lock.json' \
  ':(exclude)*yarn.lock' \
  ':(exclude)*pnpm-lock.yaml' \
  ':(exclude)*.min.js' \
  ':(exclude)*.min.css'

# 获取变更文件列表
git diff master --name-status -- \
  ':(exclude)*node_modules*' \
  ':(exclude)*dist*' \
  ':(exclude)*.lock'
```

### 3. 获取详细 diff（用于分析）

```bash
# 获取 diff 内容（限制大文件）
git diff master -- \
  ':(exclude)*node_modules*' \
  ':(exclude)*dist*' \
  ':(exclude)*.lock' \
  ':(exclude)*.min.js' \
  ':(exclude)*.min.css' \
  ':(exclude)*.png' \
  ':(exclude)*.jpg' \
  ':(exclude)*.webp' \
  ':(exclude)*.gif'
```

### 4. 获取详细 commit 信息

```bash
# 获取每个 commit 的详细信息
git log master..HEAD --pretty=format:"%h|%s|%an|%ad" --date=short
```

## 输出格式

生成的 Markdown 报告包含以下部分：

```markdown
# 🔍 Diff 分析报告

## 📊 变更概览

- **当前分支**: <branch-name>
- **对比基准**: master
- **Commit 数量**: <N> 个
- **变更统计**:
  - 新增文件: <N> 个
  - 修改文件: <N> 个
  - 删除文件: <N> 个

## 📝 功能总结

### 本次迭代主要内容

- [从 commit、和 target branch (默认是 master) diff 内容，综合整个项目代码，进行分析]

## 🗂️ 变更文件清单

### 新增文件
- `path/to/file.ts` - 简要说明

### 修改文件
- `path/to/file.ts` - 简要说明

### 删除文件
- `path/to/file.ts` - 简要说明

## 💡 代码审查建议

### 潜在问题
- [发现的问题点]

### 优化建议
- [改进建议]

## 📋 PR 描述（可选）

[可直接粘贴到 PR 的描述内容]
```

## 分析要点

### 变更分类

按文件类型分类统计：
- 源代码文件 (.ts, .js, .jsx, .tsx, .vue, .py, .java 等)
- 样式文件 (.css, .scss, .less)
- 配置文件 (.json, .yaml, .toml, .env.*)
- 文档文件 (.md, .txt)
- 测试文件 (*.test.*, *.spec.*)

### 功能总结要点

从以下方面总结：
1. Commit 信息提取主要功能
2. 新增文件判断新功能模块
3. 修改文件判断功能增强或 bug 修复
4. 删除文件判断功能移除或重构

### 审查建议要点

关注以下问题：
1. 是否有未完成代码（TODO、FIXME）
2. 是否有大量注释掉的代码
3. 是否有可疑的控制台输出（console.log）
4. 是否有安全隐患（硬编码密钥等）
5. 是否有可能的性能问题
6. 代码结构是否合理
7. 是否有重复代码
8. 是否有不必要的依赖引入，或是错误的引用
9. 模块版本号是否有更新

## 过滤规则

### 默认排除

以下类型的文件默认不分析：
- `node_modules/` 目录
- `dist/`、`build/`、`out/` 等构建产物
- `*.lock` 文件（package-lock.json, yarn.lock, pnpm-lock.yaml）
- `*.min.js`、`*.min.css` 压缩文件
- 图片文件（.png, .jpg, .gif, .webp, .svg）
- 二进制文件

### 用户自定义过滤

如果用户指定了过滤条件，在 diff 命令中追加 `:(exclude)` 规则。

## 使用示例

用户说：
- "分析一下这次迭代的变更"
- "分析一下这个需求的变更"
- "和 master 有什么不同"
- "帮我生成 PR 描述"
- "总结一下最近的代码变更"

## 注意事项

1. 确保在 git 仓库目录下执行
2. 如果当前分支就是 master，提示用户切换分支
3. 如果变更量过大（>100 个文件），建议用户缩小范围
4. diff 内容可能很长，智能截取关键部分分析