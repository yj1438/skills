#!/bin/bash

# Harness 评估执行脚本
# 在 Evaluator Agent 的引导下使用 Playwright 进行端到端测试

set -e

SPRINT_ID="${1:-}"
REPORT_DIR="docs/harness/evaluation-reports"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M)

echo "🧪 Starting Evaluation: $SPRINT_ID"
echo ""

# 1. 检查开发服务是否运行
echo "🔌 Checking development server..."
if curl -s http://localhost:5173 > /dev/null 2>&1; then
  echo "   ✅ Dev server is running"
else
  echo "   ⚠️  Dev server not running, starting..."
  npm run dev &
  DEV_PID=$!
  sleep 3
fi

# 2. 运行 Playwright E2E 测试
echo ""
echo "🎭 Running Playwright E2E tests..."
mkdir -p test-results
if npm run test:e2e -- --reporter=html 2>&1 | tee test-results/e2e-output.txt; then
  echo "   ✅ E2E Tests: PASS"
  E2E_STATUS="PASS"
else
  echo "   ❌ E2E Tests: FAIL"
  E2E_STATUS="FAIL"
fi

# 3. 生成截图报告
echo ""
echo "📸 Capturing screenshots..."
npx playwright screenshot --output=test-results/screenshots 2>/dev/null || true

# 4. 运行静态分析
echo ""
echo "📊 Running static analysis..."
echo "   TypeScript..."
TSC_RESULT=$(npm run type-check 2>&1 && echo "PASS" || echo "FAIL")
echo "   ESLint..."
LINT_RESULT=$(npm run lint 2>&1 && echo "PASS" || echo "FAIL")
echo "   Coverage..."
COVERAGE_RESULT=$(npm run test:coverage -- --run 2>&1 || true)

# 5. 生成评估报告
echo ""
echo "📝 Generating evaluation report..."

mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/$DATE-${SPRINT_ID}-evaluation.md"

cat > "$REPORT_FILE" << EOF
# Evaluation Report: $SPRINT_ID

## 基本信息

| 字段 | 值 |
|------|-----|
| Sprint ID | $SPRINT_ID |
| 评估时间 | $DATE $TIME |
| E2E 测试状态 | $E2E_STATUS |

## 自动化检查结果

| 检查项 | 结果 |
|--------|------|
| E2E 测试 | $E2E_STATUS |
| TypeScript | $TSC_RESULT |
| ESLint | $LINT_RESULT |

## E2E 测试输出

\`\`\`
$(cat test-results/e2e-output.txt 2>/dev/null || echo "No output available")
\`\`\`

## 待 Evaluator 手动评估

以下维度需要 Evaluator Agent 使用 agent-browser 和 webapp-testing 进行详细评估：

- [ ] 功能完整性 (40%): 手动验证所有用户故事
- [ ] 设计质量 (25%): 视觉检查和原创性评估
- [ ] 代码质量 (20%): 架构审查和可维护性
- [ ] 可用性 (15%): 用户体验评估

## 截图存放位置

\`test-results/screenshots/\`

---
生成时间: $(date)
EOF

echo "   ✅ Report generated: $REPORT_FILE"

# 6. 清理临时进程
if [ -n "$DEV_PID" ]; then
  kill $DEV_PID 2>/dev/null || true
fi

echo ""
echo "📊 Evaluation Summary:"
echo "   E2E Tests: $E2E_STATUS"
echo "   TypeScript: $TSC_RESULT"
echo "   Lint: $LINT_RESULT"
echo ""
echo "📄 Full report: $REPORT_FILE"
echo ""
if [ "$E2E_STATUS" = "PASS" ] && [ "$TSC_RESULT" = "PASS" ] && [ "$LINT_RESULT" = "PASS" ]; then
  echo "✅ Automated checks PASSED. Evaluator Agent should review manually."
else
  echo "❌ Some automated checks FAILED. Please fix before Evaluator review."
fi
