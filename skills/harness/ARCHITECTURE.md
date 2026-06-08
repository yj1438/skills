# Web Development Harness - 架构规范

> 本文定义了 web 应用开发中的分层架构、依赖约束、命名规范、代码标准，作为 Agent 开发的强制性规则。

## 分层架构模型

所有业务模块必须遵循 **5 层递进架构**，仅允许正向依赖：

```
┌─────────────────────────────┐
│  UI Layer (React Components)│  用户交互层
└────────────┬────────────────┘
             │ 依赖
┌────────────▼────────────────┐
│  Runtime Layer (Hooks/Stores)  状态管理层
└────────────┬────────────────┘
             │ 依赖
┌────────────▼────────────────┐
│  Service Layer (API Calls)  │  业务逻辑层
└────────────┬────────────────┘
             │ 依赖
┌────────────▼────────────────┐
│  Repository Layer (Data)    │  数据访问层
└────────────┬────────────────┘
             │ 依赖
┌────────────▼────────────────┐
│  Types Layer (Interfaces)   │  类型定义层
└─────────────────────────────┘
```

### 各层职责

| 层级 | 文件位置 | 职责 | 示例 |
|------|---------|------|------|
| **Types** | `src/types/*.ts` | 定义数据结构、API 接口、常量 | `User`, `TodoItem`, `ApiResponse` |
| **Repository** | `src/repos/*.ts` | 数据库操作、数据转换、缓存逻辑 | `getUserById()`, `createTodo()` |
| **Service** | `src/services/*.ts` | 业务逻辑、验证、编排 | `validateTodo()`, `processTodoCreate()` |
| **Runtime** | `src/hooks/*.ts`, `src/stores/*.ts` | React 状态、全局状态、业务状态机 | `useTodoList()`, `TodoStore` |
| **UI** | `src/components/`, `src/pages/` | React 组件、页面布局、交互 | `TodoList.tsx`, `TodoForm.tsx` |

### 正向依赖示例 ✅

```typescript
// ✅ GOOD: UI → Runtime → Service → Repository → Types
// components/TodoList.tsx
import { useTodoList } from '@/hooks/useTodoList'  // Runtime

export const TodoList = () => {
  const { todos, loading } = useTodoList()
  return <div>{todos.map(t => <TodoItem key={t.id} todo={t} />)}</div>
}

// hooks/useTodoList.ts
import { fetchTodos } from '@/services/todoService'  // Service

export const useTodoList = () => {
  const [todos, setTodos] = useState([])
  useEffect(() => {
    fetchTodos().then(setTodos)
  }, [])
  return { todos }
}

// services/todoService.ts
import { getTodosFromDb } from '@/repos/todoRepo'  // Repository

export const fetchTodos = async () => {
  return getTodosFromDb()
}

// repos/todoRepo.ts
import { Todo } from '@/types/todo'  // Types

export const getTodosFromDb = async (): Promise<Todo[]> => {
  // 数据库查询
}
```

### 反向依赖示例 ❌

```typescript
// ❌ BAD: Service 直接调用 UI 组件
import { TodoList } from '@/components/TodoList'
export const doSomething = () => {
  // 错误：Service 不应该导入 UI 组件
}

// ❌ BAD: Repository 中混入业务逻辑
export const getTodosFromDb = async () => {
  if (!user.isAdmin) return []  // 业务逻辑应在 Service 层
}

// ❌ BAD: UI 组件直接操作数据库
import { db } from '@/db'
export const TodoItem = () => {
  const handleClick = () => {
    db.todos.delete(id)  // 应该通过 Service 访问
  }
}
```

---

## 代码规范与硬性约束

### 1. 类型安全 (必须)

**规则**: 所有数据入口必须用 Zod 等库做边界校验

```typescript
// types/todo.ts
import { z } from 'zod'

export const TodoSchema = z.object({
  id: z.string().uuid(),
  title: z.string().min(1).max(255),
  completed: z.boolean().default(false),
  createdAt: z.date(),
})

export type Todo = z.infer<typeof TodoSchema>

// services/todoService.ts
export const createTodo = async (data: unknown): Promise<Todo> => {
  const validated = TodoSchema.parse(data)  // 强制校验
  return saveTodo(validated)
}

// API 路由必须验证入参
app.post('/todos', (req, res) => {
  const validated = TodoSchema.partial().parse(req.body)
  // ...
}
```

**Linter 规则**: 禁止使用 `any` 类型，违规代码 CI 失败

---

### 2. 命名规范

**文件命名**:
- 组件: PascalCase (`TodoItem.tsx`, `TodoForm.tsx`)
- hooks: camelCase with prefix (`useTodoList.ts`, `useTodoForm.ts`)
- services: camelCase with suffix (`todoService.ts`)
- types: kebab-case (`todo.ts`, `api-response.ts`)
- 存储: camelCase with suffix (`todoStore.ts`)

**变量命名**:
- React 组件: `PascalCase` (`<TodoList />`)
- 函数: `camelCase` (`const fetchTodos = () => {}`)
- 常量: `UPPER_SNAKE_CASE` (`const MAX_TODO_LENGTH = 255`)
- 布尔值: `is*` or `has*` prefix (`isLoading`, `hasError`)

**函数/API 命名**:
- 查询: `get*` or `fetch*` (`getTodo`, `fetchTodos`)
- 创建: `create*` (`createTodo`)
- 更新: `update*` (`updateTodo`)
- 删除: `delete*` (`deleteTodo`)
- 校验: `validate*` or `is*` (`validateTodo`, `isTodoValid`)

---

### 3. 文件大小与复杂度限制

| 文件类型 | 行数上限 | 理由 |
|---------|--------|------|
| React 组件 | 250 行 | 保持组件聚焦，易测试 |
| 服务函数 | 150 行 | 避免单函数逻辑过复杂 |
| Hooks | 120 行 | 复杂逻辑分离成多个 hook |
| Types 定义 | 300 行 | 保持类型文件可读 |

**Linter 规则**: 超限代码 CI 失败，需要拆分

---

### 4. 结构化日志与调试

所有异步操作、关键业务逻辑必须记录结构化日志：

```typescript
import { logger } from '@/utils/logger'

export const createTodo = async (data: CreateTodoInput) => {
  logger.info('Creating todo', { input: data })
  try {
    const validated = TodoSchema.parse(data)
    const result = await saveTodo(validated)
    logger.info('Todo created successfully', { todoId: result.id })
    return result
  } catch (error) {
    logger.error('Failed to create todo', { error, input: data })
    throw error
  }
}
```

**日志格式**: JSON 结构化
```json
{
  "timestamp": "2026-03-31T16:09:00Z",
  "level": "INFO",
  "message": "Todo created successfully",
  "context": { "todoId": "uuid-xxx", "userId": "uuid-yyy" }
}
```

---

### 5. 错误处理与边界保护

**规则**: 所有异步函数必须有错误处理

```typescript
// ✅ GOOD
export const fetchTodos = async (): Promise<Todo[]> => {
  try {
    const response = await api.get('/todos')
    return response.data
  } catch (error) {
    if (error instanceof NetworkError) {
      logger.error('Network error while fetching todos', { error })
      throw new AppError('Unable to fetch todos', 'NETWORK_ERROR')
    }
    throw error
  }
}

// ❌ BAD - 无错误处理
export const fetchTodos = async (): Promise<Todo[]> => {
  const response = await api.get('/todos')
  return response.data
}
```

---

### 6. 前端组件规范

**组件结构**:
```typescript
import React from 'react'
import { useTodoList } from '@/hooks/useTodoList'  // Runtime
import { TodoItem } from '@/components/TodoItem'   // 子组件
import styles from './TodoList.module.css'         // 样式

interface TodoListProps {
  onItemClick?: (id: string) => void
}

/**
 * 展示待办清单
 * @component
 * @example
 * <TodoList onItemClick={handleClick} />
 */
export const TodoList: React.FC<TodoListProps> = ({ onItemClick }) => {
  const { todos, loading, error } = useTodoList()

  if (loading) return <div>Loading...</div>
  if (error) return <div>Error: {error.message}</div>

  return (
    <ul className={styles.list}>
      {todos.map(todo => (
        <TodoItem
          key={todo.id}
          todo={todo}
          onClick={() => onItemClick?.(todo.id)}
        />
      ))}
    </ul>
  )
}
```

**规则**:
- 必须有 TypeScript 类型定义
- 必须有 JSDoc 注释说明组件用途
- Props 必须定义接口
- 保持组件纯函数特性
- 复杂逻辑移到 hooks 或 services

---

### 7. 测试覆盖率要求

| 模块类型 | 覆盖率目标 | 说明 |
|---------|----------|------|
| 业务逻辑 (Service) | 80%+ | 关键路径必须测试 |
| 数据访问 (Repo) | 70%+ | 重点测试异常情况 |
| React 组件 | 60%+ | 重点测试交互与状态变化 |
| Hooks | 70%+ | 测试各种输入状态 |

**Linter 规则**: 低于阈值的 PR 无法合并

---

## 禁止的反模式

| 反模式 | 原因 | 正确做法 |
|--------|------|---------|
| 全局变量 | 难以追踪、测试困难 | 使用 React Context 或 Store |
| 循环依赖 | 导致编译错误、难维护 | 重构分离关注点 |
| 回调地狱 | 可读性差 | 使用 async/await |
| 重复代码 | 维护困难 | 提取共享工具函数 |
| 魔法数字 | 难以理解 | 定义命名常量 |
| 副作用污染 | 难测试 | 纯函数 + 显式依赖 |
| 直接修改入参 | 易产生 bug | 返回新对象 |

---

## 架构校验清单

对每个 feature 开发完成后，生成检查：

- [ ] 所有数据流遵循 5 层架构
- [ ] 无反向依赖
- [ ] 所有公共函数有类型定义
- [ ] 所有 API 入口有 Zod 校验
- [ ] 所有异步函数有错误处理
- [ ] 所有组件有 JSDoc 注释
- [ ] 命名规范一致性
- [ ] 文件大小符合限制
- [ ] 测试覆盖率符合要求
- [ ] Linter 无错误 (`npm run lint`)
- [ ] 类型检查通过 (`npm run type-check`)

---

## 技术栈推荐

基于 "模型友好型" 原则，推荐使用以下技术栈：

**前端**:
- 框架: React 18+
- 构建: Vite
- 语言: TypeScript
- 样式: Tailwind CSS + Shadcn UI
- 状态: Zustand 或 TanStack Query
- 表单: React Hook Form + Zod
- 测试: Vitest + Testing Library + Playwright

**后端** (如需):
- 框架: FastAPI (Python) 或 Express (Node.js)
- 数据库: PostgreSQL + Prisma ORM
- API: REST + OpenAPI/Swagger
- 测试: pytest 或 Jest

**DevOps**:
- 版本控制: Git (主分支保护)
- CI/CD: GitHub Actions 或 GitLab CI
- 代码质量: ESLint + Prettier + TypeScript
- 监控: 结构化日志 (JSON) + 基础指标

---

## 如何验证架构合规性

由 CI/CD 自动执行，包含但不限于：

1. **静态分析** (`eslint`, `tsc`)
2. **依赖分析** (检查循环依赖、逆向依赖)
3. **类型检查** (no `any`, 覆盖率)
4. **代码复杂度** (圈复杂度、文件大小)
5. **测试覆盖率** (最小阈值检查)
6. **端到端测试** (核心流程验证)

CI 失败则 PR 阻塞，确保所有代码都符合规范。
