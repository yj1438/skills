#!/bin/bash

# Harness 项目初始化脚本
# 用法: ./init-project.sh <project-name> "<description>"

set -e

PROJECT_NAME="${1:-my-project}"
PROJECT_DESC="${2:-A web application}"
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y%m%d%H%M%S)

echo "🚀 Initializing Harness Project: $PROJECT_NAME"
echo "Description: $PROJECT_DESC"
echo ""

# 1. 创建项目目录结构
echo "📁 Creating directory structure..."
mkdir -p src/{components,pages,hooks,services,repos,types,utils,styles}
mkdir -p src/components/{ui,layout,features}
mkdir -p public
mkdir -p tests/{unit,e2e}
mkdir -p docs/{specs,plans,harness}
mkdir -p docs/harness/evaluation-reports
mkdir -p .harness/templates
mkdir -p scripts

# 2. 初始化前端项目 (Vite + React + TypeScript)
echo "⚡ Initializing Vite + React + TypeScript..."
npm create vite@latest . -- --template react-ts

# 3. 安装核心依赖
echo "📦 Installing dependencies..."
npm install

# 4. 安装 Tailwind CSS
echo "🎨 Setting up Tailwind CSS..."
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# 5. 安装 Shadcn UI
echo "🧩 Setting up Shadcn UI..."
npx shadcn@latest init -y

# 6. 安装常用工具库
echo "🔧 Installing utility libraries..."
npm install zustand @tanstack/react-query react-hook-form zod
npm install -D @types/node

# 7. 安装测试工具
echo "🧪 Setting up testing tools..."
npm install -D vitest @testing-library/react @testing-library/jest-dom @playwright/test
npx playwright install

# 8. 创建 Tailwind 配置
echo "⚙️ Creating Tailwind config..."
cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ["class"],
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
  ],
  theme: {
    container: {
      center: true,
      padding: "2rem",
      screens: {
        "2xl": "1400px",
      },
    },
    extend: {
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
          to: { height: "0" },
        },
      },
      animation: {
        "accordion-down": "accordion-down 0.2s ease-out",
        "accordion-up": "accordion-up 0.2s ease-out",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
}
EOF

npm install -D tailwindcss-animate

# 9. 创建 TypeScript 配置
echo "📝 Updating TypeScript config..."
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
EOF

# 10. 创建 ESLint 配置
echo "🔍 Setting up ESLint..."
npm install -D eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint-plugin-react eslint-plugin-react-hooks eslint-plugin-jsx-a11y

cat > .eslintrc.cjs << 'EOF'
module.exports = {
  root: true,
  env: { browser: true, es2020: true },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:react/recommended',
    'plugin:react/jsx-runtime',
    'plugin:react-hooks/recommended',
    'plugin:jsx-a11y/recommended',
  ],
  ignorePatterns: ['dist', '.eslintrc.cjs'],
  parser: '@typescript-eslint/parser',
  plugins: ['react-refresh'],
  rules: {
    'react-refresh/only-export-components': [
      'warn',
      { allowConstantExport: true },
    ],
    '@typescript-eslint/no-explicit-any': 'error',
    '@typescript-eslint/no-unused-vars': 'error',
  },
}
EOF

# 11. 创建 package.json scripts
echo "📜 Adding npm scripts..."
npm pkg set scripts.dev="vite"
npm pkg set scripts.build="tsc && vite build"
npm pkg set scripts.preview="vite preview"
npm pkg set scripts.lint="eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0"
npm pkg set scripts."type-check"="tsc --noEmit"
npm pkg set scripts.test="vitest"
npm pkg set scripts."test:e2e"="playwright test"
npm pkg set scripts."test:coverage"="vitest --coverage"

# 12. 创建基础文件
echo "📄 Creating base files..."

# src/index.css
cat > src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
 
@layer base {
  :root {
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    --card: 0 0% 100%;
    --card-foreground: 222.2 84% 4.9%;
    --popover: 0 0% 100%;
    --popover-foreground: 222.2 84% 4.9%;
    --primary: 222.2 47.4% 11.2%;
    --primary-foreground: 210 40% 98%;
    --secondary: 210 40% 96.1%;
    --secondary-foreground: 222.2 47.4% 11.2%;
    --muted: 210 40% 96.1%;
    --muted-foreground: 215.4 16.3% 46.9%;
    --accent: 210 40% 96.1%;
    --accent-foreground: 222.2 47.4% 11.2%;
    --destructive: 0 84.2% 60.2%;
    --destructive-foreground: 210 40% 98%;
    --border: 214.3 31.8% 91.4%;
    --input: 214.3 31.8% 91.4%;
    --ring: 222.2 84% 4.9%;
    --radius: 0.5rem;
  }
 
  .dark {
    --background: 222.2 84% 4.9%;
    --foreground: 210 40% 98%;
    --card: 222.2 84% 4.9%;
    --card-foreground: 210 40% 98%;
    --popover: 222.2 84% 4.9%;
    --popover-foreground: 210 40% 98%;
    --primary: 210 40% 98%;
    --primary-foreground: 222.2 47.4% 11.2%;
    --secondary: 217.2 32.6% 17.5%;
    --secondary-foreground: 210 40% 98%;
    --muted: 217.2 32.6% 17.5%;
    --muted-foreground: 215 20.2% 65.1%;
    --accent: 217.2 32.6% 17.5%;
    --accent-foreground: 210 40% 98%;
    --destructive: 0 62.8% 30.6%;
    --destructive-foreground: 210 40% 98%;
    --border: 217.2 32.6% 17.5%;
    --input: 217.2 32.6% 17.5%;
    --ring: 212.7 26.8% 83.9%;
  }
}
 
@layer base {
  * {
    @apply border-border;
  }
  body {
    @apply bg-background text-foreground;
  }
}
EOF

# src/utils/logger.ts
cat > src/utils/logger.ts << 'EOF'
interface LogContext {
  [key: string]: unknown;
}

const formatTimestamp = (): string => {
  return new Date().toISOString();
};

export const logger = {
  info: (message: string, context?: LogContext): void => {
    console.log(JSON.stringify({
      timestamp: formatTimestamp(),
      level: 'INFO',
      message,
      context,
    }));
  },

  error: (message: string, context?: LogContext): void => {
    console.error(JSON.stringify({
      timestamp: formatTimestamp(),
      level: 'ERROR',
      message,
      context,
    }));
  },

  warn: (message: string, context?: LogContext): void => {
    console.warn(JSON.stringify({
      timestamp: formatTimestamp(),
      level: 'WARN',
      message,
      context,
    }));
  },

  debug: (message: string, context?: LogContext): void => {
    if (import.meta.env.DEV) {
      console.debug(JSON.stringify({
        timestamp: formatTimestamp(),
        level: 'DEBUG',
        message,
        context,
      }));
    }
  },
};
EOF

# src/lib/utils.ts (for shadcn)
mkdir -p src/lib
cat > src/lib/utils.ts << 'EOF'
import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"
 
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
EOF

npm install clsx tailwind-merge

# 13. 创建 Harness 文件
echo "📋 Setting up Harness files..."

# Feature list
cat > docs/harness/feature-list.json << EOF
{
  "version": "1.0",
  "project": "$PROJECT_NAME",
  "description": "$PROJECT_DESC",
  "features": [],
  "technical_stack": {
    "frontend": "React 18 + Vite + TypeScript + Tailwind + Shadcn UI",
    "testing": "Playwright + Vitest"
  },
  "completion_status": {
    "completed_features": 0,
    "total_features": 0,
    "completion_percentage": 0
  }
}
EOF

# Progress tracking
cat > docs/harness/progress.md << EOF
# Progress Tracking

## 项目概览

| 字段 | 值 |
|------|-----|
| 项目名 | $PROJECT_NAME |
| 开始日期 | $DATE |
| 当前状态 | 初始化完成 |
| 完成度 | 0% |

## 当前轮次信息

| 字段 | 值 |
|------|-----|
| 轮次 ID | round-1 |
| 开发 Feature | 待选择 |
| 当前状态 | 准备开始 |

## Git 提交历史

\`\`\`
项目刚初始化，暂无提交
\`\`\`

## 变更日志

| 日期 | 变更内容 | 变更人 |
|------|---------|-------|
| $DATE | 初始化项目 | init-project.sh |
EOF

# 14. 初始化 Git
echo "📦 Initializing Git repository..."
git init
cat > .gitignore << 'EOF'
# Dependencies
node_modules
.pnp
.pnp.js

# Build
dist
build

# Testing
coverage

# IDE
.vscode
.idea

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
.env.*.local

# Logs
*.log
npm-debug.log*

# Misc
*.tsbuildinfo
EOF

git add .
git commit -m "feat: Initialize project with Harness framework

- Set up Vite + React + TypeScript
- Configure Tailwind CSS + Shadcn UI
- Add testing tools (Vitest + Playwright)
- Create Harness directory structure
- Add feature-list.json and progress.md"

# 15. 创建 Vite 配置
cat > vite.config.ts << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react-swc'
import path from 'path'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
})
EOF

# 16. 创建 Playwright 配置
cat > playwright.config.ts << 'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
});
EOF

echo ""
echo "✅ Harness Project Initialized Successfully!"
echo ""
echo "📂 Project: $PROJECT_NAME"
echo "📝 Description: $PROJECT_DESC"
echo ""
echo "🚀 Next Steps:"
echo "   1. Run 'npm run dev' to start development server"
echo "   2. Use Planner Agent to generate feature-list.json"
echo "   3. Start development with Generator Agent"
echo "   4. Evaluator Agent will validate each feature"
echo ""
echo "📚 Documentation:"
echo "   - AGENTS.md: Harness workflow guide"
echo "   - ARCHITECTURE.md: Architecture and coding standards"
echo "   - docs/harness/feature-list.json: Feature tracking"
echo "   - docs/harness/progress.md: Progress tracking"
echo ""
