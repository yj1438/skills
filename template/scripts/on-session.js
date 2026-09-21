// SessionStart 钩子示例：演示 hooks/hooks.json 如何指向脚本。
// 说明：
// - ${CLAUDE_PLUGIN_ROOT} 由宿主注入，指向插件根目录
// - 钩子通过 stdout（JSON 或纯文本）与 exit code 和宿主通信
// - Codex 侧：捆绑的 hooks 在用户审查信任前不会被执行

console.log("example-plugin: session started");
