#!/usr/bin/env node
// 示例脚本：演示 skill 内 scripts/ 的写法。
// 原则：确定性逻辑放脚本（可测试、可复跑），判断性逻辑放 SKILL.md 指令。
// 零第三方依赖，node >= 18。

const args = process.argv.slice(2);

if (args.length === 0) {
  console.error("用法: node example.js <输入>");
  process.exit(1);
}

const input = args[0];
console.log(JSON.stringify({ ok: true, input, at: new Date().toISOString() }));
