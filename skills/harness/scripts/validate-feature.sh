#!/bin/bash

# Harness Feature 校验脚本
# 用法: ./validate-feature.sh <feature-id>

set -e

FEATURE_ID="${1:-}"
FEATURE_LIST="docs/harness/feature-list.json"

if [ -z "$FEATURE_ID" ]; then
  echo "❌ Usage: ./validate-feature.sh <feature-id>"
  exit 1
fi

echo "🔍 Validating Feature: $FEATURE_ID"
echo ""

# 1. 检查 feature-list.json 存在
if [ ! -f "$FEATURE_LIST" ]; then
  echo "❌ feature-list.json not found"
  exit 1
fi

# 2. 读取 feature 信息
FEATURE=$(cat "$FEATURE_LIST" | python3 -c "
import json, sys
data = json.load(sys.stdin)
feature = next((f for f in data['features'] if f['id'] == '$FEATURE_ID'), None)
if feature:
    print(json.dumps(feature, ensure_ascii=False, indent=2))
else:
    print('NOT_FOUND')
")

if [ "$FEATURE" = "NOT_FOUND" ]; then
  echo "❌ Feature $FEATURE_ID not found in feature-list.json"
  exit 1
fi

echo "📋 Feature Info:"
echo "$FEATURE"
echo ""

# 3. TypeScript 类型检查
echo "📝 Running TypeScript check..."
if npm run type-check 2>&1; then
  echo "   ✅ TypeScript: PASS"
else
  echo "   ❌ TypeScript: FAIL"
  VALIDATION_FAILED=1
fi

# 4. ESLint 检查
echo "🔍 Running ESLint..."
if npm run lint 2>&1; then
  echo "   ✅ ESLint: PASS"
else
  echo "   ❌ ESLint: FAIL"
  VALIDATION_FAILED=1
fi

# 5. 单元测试
echo "🧪 Running unit tests..."
if npm run test -- --run 2>&1; then
  echo "   ✅ Unit Tests: PASS"
else
  echo "   ❌ Unit Tests: FAIL"
  VALIDATION_FAILED=1
fi

# 6. 构建检查
echo "🏗️ Running build check..."
if npm run build 2>&1; then
  echo "   ✅ Build: PASS"
else
  echo "   ❌ Build: FAIL"
  VALIDATION_FAILED=1
fi

echo ""

if [ -n "$VALIDATION_FAILED" ]; then
  echo "❌ Validation FAILED. Please fix the issues above."
  exit 1
fi

echo "✅ All validation checks PASSED!"
echo ""
echo "🎯 Next Steps:"
echo "   1. Run E2E tests with Playwright to verify functionality"
echo "   2. Have Evaluator Agent review the feature"
echo "   3. Update feature-list.json passes to true"
echo "   4. Commit the changes"
