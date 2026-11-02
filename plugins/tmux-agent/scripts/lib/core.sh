#!/usr/bin/env bash
set -euo pipefail

# Shared lifecycle and transport. CLI-specific behavior lives in adapters/.
session_option() {
  local handle
  handle=$(session_handle "$1") || return 1
  tmux show-options -v -t "$handle" "@${ADAPTER_METADATA}_$2" 2>/dev/null || true
}

set_session_option() {
  local handle
  handle=$(session_handle "$1") || return 1
  tmux set-option -t "$handle" "@${ADAPTER_METADATA}_$2" "$3"
}

# tmux 仅负责可靠传输；任务判断、授权边界和目标回复解释由调用侧负责。
usage() {
  cat <<'EOF'
Usage:
  tmux-agent.sh <agent> list
  tmux-agent.sh <agent> name [cwd]
  tmux-agent.sh <agent> format-name <project> [branch]
  tmux-agent.sh <agent> start [cwd]
  tmux-agent.sh <agent> target [session]
  tmux-agent.sh <agent> attach [session]
  tmux-agent.sh <agent> destroy [session]
  tmux-agent.sh <agent> send <session:window.pane> [message]
  tmux-agent.sh <agent> capture <session:window.pane> [history-lines]
  tmux-agent.sh <agent> status <session:window.pane>
  tmux-agent.sh <agent> address <session:window.pane>
  tmux-agent.sh <agent> address <pane-id>
  tmux-agent.sh <agent> send-checked <pane-id> <expected-pid> <expected-native-id> [message]

send 未提供消息参数时从 stdin 读取。
target/attach/destroy 未提供 session 参数时，使用 PWD 派生的稳定名称。
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

# target 是 pane 级标识（session:window.pane）；发送和读取前都先确认其存在。
require_target() {
  local target=$1 actual
  actual=$(tmux display-message -p -t "$target" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null) || {
    printf 'tmux target not found: %s\n' "$target" >&2
    exit 1
  }
  if [[ "$actual" != "$target" ]]; then
    printf 'refusing non-exact target: %s (resolved to %s)\n' "$target" "$actual" >&2
    exit 1
  fi
}

# session 的精确存在性统一走 session_exists_exact，避免 tmux 的前缀匹配误命中。
require_session() {
  local session=$1
  session_exists_exact "$session" || {
    printf 'tmux session not found: %s\n' "$session" >&2
    exit 1
  }
}

# 部分 tmux 子命令对“=精确匹配”支持不一致，因此直接枚举后逐字比较名称。
session_exists_exact() {
  session_handle "$1" >/dev/null
}

# Session IDs work across tmux subcommands that do not accept =name syntax.
session_handle() {
  local expected=$1 actual handle
  while IFS=' ' read -r handle actual; do
    if [[ "$actual" == "$expected" ]]; then
      printf '%s\n' "$handle"
      return 0
    fi
  done < <(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null || true)
  return 1
}

# Keep lookup failures outside tmux argument expansion: an empty -t is a default target.
require_session_handle() {
  local session=$1 handle
  if ! handle=$(session_handle "$session") || [[ ! "$handle" =~ ^\$[0-9]+$ ]]; then
    printf 'refusing unresolved session handle: %s\n' "$session" >&2
    return 1
  fi
  printf '%s\n' "$handle"
}

# 目标独立的 metadata 保留旧 Claude 契约，并防止跨适配器接管。
require_managed_session() {
  local session=$1
  require_session "$session"
  if [[ "$(session_option "$session" managed)" != "1" ]]; then
    printf 'refusing to manage unrecognized session: %s\n' "$session" >&2
    exit 1
  fi
}

# 新会话使用已记录 pane ID；旧会话仅在全 session 唯一 pane 时兼容。
resolve_session_target() {
  local session=$1 pane owner target handle dead
  pane=$(session_option "$session" pane_id) || return 1
  if [[ -n "$pane" ]]; then
    if [[ ! "$pane" =~ ^%[0-9]+$ ]]; then
      printf 'refusing invalid pane metadata: %s\n' "$session" >&2
      return 1
    fi
    owner=$(tmux display-message -p -t "$pane" '#{session_name}') || return 1
    if [[ "$owner" != "$session" ]]; then
      printf 'refusing stale pane metadata: %s\n' "$session" >&2
      return 1
    fi
    target=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}.#{pane_index}') || return 1
  else
    handle=$(session_handle "$session") || return 1
    target=$(tmux list-panes -s -t "$handle" -F '#{session_name}:#{window_index}.#{pane_index}') || return 1
    if [[ -z "$target" || "$target" == *$'\n'* ]]; then
      printf 'refusing ambiguous or missing pane: %s\n' "$session" >&2
      return 1
    fi
  fi
  dead=$(tmux display-message -p -t "$target" '#{pane_dead}') || return 1
  if [[ "$dead" != 0 ]]; then
    printf 'refusing dead or unavailable pane: %s\n' "$target" >&2
    return 1
  fi
  printf '%s\n' "$target"
}

# 已有会话的权限契约必须与适配器一致。
require_session_permission_mode() {
  local session=$1
  local actual_mode
  actual_mode=$(session_option "$session" permission_mode)
  if [[ "$actual_mode" != "$ADAPTER_PERMISSION_MODE" ]]; then
    actual_mode=${actual_mode:-unset}
    printf 'refusing to use session %s: permission mode mismatch (%s != %s)\n' \
      "$session" "$actual_mode" "$ADAPTER_PERMISSION_MODE" >&2
    exit 1
  fi
}

is_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

new_session_uuid() {
  local value=""
  if command -v uuidgen >/dev/null 2>&1; then
    value=$(uuidgen)
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    value=$(</proc/sys/kernel/random/uuid)
  elif command -v python3 >/dev/null 2>&1; then
    value=$(python3 -c 'import uuid; print(uuid.uuid4())')
  else
    printf 'cannot generate session UUID: uuidgen, /proc random uuid, and python3 are unavailable\n' >&2
    exit 1
  fi
  value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  if ! is_uuid "$value"; then
    printf 'generated invalid session UUID: %s\n' "$value" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

require_target_session_contract() {
  local target=$1
  local session root actual_root expected
  session=$(tmux display-message -p -t "$target" '#{session_name}')
  require_managed_session "$session"
  require_session_permission_mode "$session"
  adapter_validate_session "$session"
  root=$(project_root "$PWD")
  actual_root=$(session_option "$session" project_root)
  if [[ "$actual_root" != "$root" ]]; then
    printf 'refusing to reuse session %s: project root mismatch (%s != %s)\n' \
      "$session" "$actual_root" "$root" >&2
    exit 1
  fi
  expected=$(resolve_session_target "$session")
  if [[ "$expected" != "$target" ]]; then
    printf 'refusing non-managed pane: %s (expected %s)\n' "$target" "$expected" >&2
    exit 1
  fi
}

# Windows npm 包装的 CLI（codex/claude 经 node 运行）在 pane_current_command
# 里只显示 node(.exe)。回退证据是 pane_start_command —— 该值是 Helper 创建
# 面板时写入的启动命令，面板内容无法伪造；且仅当前台仍是 node 包装进程时
# 才接受，避免把消息送进已切换到其它程序的 pane。
pane_runs_cli() {
  local target=$1 command start token base found
  command=$(tmux display-message -p -t "$target" '#{pane_current_command}') || return 1
  adapter_is_process "$command" && return 0
  base=${command##*/}
  base=${base##*\\}
  [[ "$base" == node || "$base" == node.exe ]] || return 1
  start=$(tmux display-message -p -t "$target" '#{pane_start_command}') || return 1
  found=""
  for token in $start; do
    token=${token##*/}
    token=${token##*\\}
    if [[ "$token" == "$ADAPTER_CLI" ]]; then
      found=1
      break
    fi
  done
  [[ -n "$found" ]]
}

# send 只允许写入当前前台命令确认为目标 CLI 的 pane，避免消息落到 shell 等进程。
require_agent_pane() {
  local target=$1
  local operation=${2:-send}
  local command
  command=$(tmux display-message -p -t "$target" '#{pane_current_command}')
  if ! adapter_is_process "$command" && ! pane_runs_cli "$target"; then
    printf 'Refusing to %s: target %s is running %s, not a recognized %s process\n' \
      "$operation" "$target" "$command" "$ADAPTER_CLI" >&2
    exit 1
  fi
}

# 没有 tmux server 时返回空列表而不是把“no server running”当成失败噪音。
cmd_list() {
  if ! tmux has-session 2>/dev/null; then
    return 0
  fi
  tmux list-panes -a -F "target=#{session_name}:#{window_index}.#{pane_index} command=#{pane_current_command} cwd=#{pane_current_path} active=#{pane_active} dead=#{pane_dead} managed=#{@${ADAPTER_METADATA}_managed} permission_mode=#{@${ADAPTER_METADATA}_permission_mode} native_session_id=#{@${ADAPTER_METADATA}_session_id}"
}

# tmux 会把 session name 中的“.”静默转换成“_”，“:”还会参与 target 解析。
# 先编码已有“%”，再编码“.”和“:”，使名称保持可区分且可逆。
encode_name_component() {
  local value=$1
  value=${value//%/%25}
  value=${value//./%2E}
  value=${value//:/%3A}
  printf '%s' "$value"
}

# Git 项目以仓库根目录为项目边界；非 Git 目录退化为规范化 cwd。
project_root() {
  local cwd=${1:-$PWD}
  if [[ ! -d "$cwd" ]]; then
    printf 'working directory does not exist: %s\n' "$cwd" >&2
    return 1
  fi
  if command -v git >/dev/null 2>&1 && git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$cwd" rev-parse --show-toplevel
  else
    (cd "$cwd" && pwd -P)
  fi
}

# 稳定名称由适配器前缀、项目名和分支组成；无分支或 detached HEAD 使用 main。
stable_session_name() {
  local cwd=${1:-$PWD}
  local root project branch
  root=$(project_root "$cwd")
  project=$(basename "$root")
  branch=""
  if command -v git >/dev/null 2>&1; then
    branch=$(git -C "$root" branch --show-current 2>/dev/null || true)
  fi
  stable_session_name_from_parts "$project" "$branch"
}

# 纯计算入口：用于文档、评审或假设场景，避免 Agent 手工复刻编码规则。
stable_session_name_from_parts() {
  local project=${1:?project name is required}
  local branch=${2:-main}
  branch=${branch:-main}
  printf '%s-%s-%s\n' "$ADAPTER_PREFIX" "$(encode_name_component "$project")" "$(encode_name_component "$branch")"
}

cmd_name() {
  stable_session_name "${1:-$PWD}"
}

cmd_format_name() {
  stable_session_name_from_parts "${1:?project name is required}" "${2:-main}"
}

report_start_failure() {
  printf 'failed to start agent=%s session=%s: CLI exited, did not become recognizable, or tmux initialization failed; check CLI startup/configuration and capture/attach if the session still exists\n' \
    "$AGENT" "$1" >&2
}

# A live bootstrap shell is not evidence that the CLI started. Bound the wait,
# then check once more for an immediately exiting process; this is not TUI readiness.
check_started_pane() {
  local target=$1 attempt command dead
  for attempt in {1..20}; do
    dead=$(tmux display-message -p -t "$target" '#{pane_dead}') || return 1
    [[ "$dead" == 0 ]] || return 1
    command=$(tmux display-message -p -t "$target" '#{pane_current_command}') || return 1
    if adapter_is_process "$command" || pane_runs_cli "$target"; then
      sleep 0.1
      dead=$(tmux display-message -p -t "$target" '#{pane_dead}') || return 1
      [[ "$dead" == 0 ]]
      return
    fi
    sleep 0.1
  done
  return 1
}

cmd_start() {
  local cwd=${1:-$PWD}
  local session root actual_root target launch
  session=$(stable_session_name "$cwd")
  root=$(project_root "$cwd")

  require_command "$ADAPTER_CLI"
  # start 是幂等的：同名且管理标记、项目根、权限模式一致时直接复用；身份不一致则拒绝接管。
  if session_exists_exact "$session"; then
    require_managed_session "$session"
    actual_root=$(session_option "$session" project_root)
    if [[ "$actual_root" != "$root" ]]; then
      printf 'refusing to reuse session %s: project root mismatch (%s != %s)\n' \
        "$session" "$actual_root" "$root" >&2
      exit 1
    fi
    require_session_permission_mode "$session"
    adapter_validate_session "$session"
    target=$(resolve_session_target "$session")
    require_agent_pane "$target" reuse
    printf 'reused agent=%s session=%s target=%s cwd=%s permission_mode=%s native_session_id=%s\n' \
      "$AGENT" "$session" "$target" "$root" "$ADAPTER_PERMISSION_MODE" "$(session_option "$session" session_id)"
    return 0
  fi

  adapter_prepare_start
  # Existing tmux servers may retain an older PATH; launch the CLI we checked here.
  ADAPTER_ARGV[0]=$(command -v "$ADAPTER_CLI")
  # Quote argv as data before passing the single tmux shell-command string.
  printf -v launch '%q ' env -u NO_COLOR "${ADAPTER_ARGV[@]}"
  if ! target=$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -c "$cwd" "$launch"); then
    report_start_failure "$session"
    return 1
  fi
  # Explicit chaining keeps failures observable even inside this conditional.
  # This is a brief liveness check, not a claim that the CLI is ready for input.
  if ! { set_session_option "$session" managed 1 &&
         set_session_option "$session" project_root "$root" &&
         set_session_option "$session" permission_mode "$ADAPTER_PERMISSION_MODE" &&
         set_session_option "$session" session_id "$AGENT_SESSION_ID" &&
         set_session_option "$session" pane_id "$target" &&
         check_started_pane "$target" &&
         target=$(resolve_session_target "$session"); }; then
    report_start_failure "$session"
    return 1
  fi
  printf 'started agent=%s session=%s target=%s cwd=%s permission_mode=%s native_session_id=%s\n' \
    "$AGENT" "$session" "$target" "$root" "$ADAPTER_PERMISSION_MODE" "$AGENT_SESSION_ID"
}

cmd_target() {
  local session=${1:-}
  local root actual_root
  session=${session:-$(stable_session_name "$PWD")}
  require_managed_session "$session"
  # 找到同名 session 后仍需核对项目根；不允许仅凭名称接管另一份同名 checkout。
  root=$(project_root "$PWD")
  actual_root=$(session_option "$session" project_root)
  if [[ "$actual_root" != "$root" ]]; then
    printf 'refusing to reuse session %s: project root mismatch (%s != %s)\n' \
      "$session" "$actual_root" "$root" >&2
    exit 1
  fi
  resolve_session_target "$session"
}

# 用户在 tmux 外调用时 attach；已经位于 tmux 内时切换当前 client，避免嵌套会话。
cmd_attach() {
  local session=${1:-} handle
  session=${session:-$(stable_session_name "$PWD")}
  require_session "$session"
  handle=$(require_session_handle "$session") || return 1
  if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "$handle"
  fi
  exec tmux attach-session -t "$handle"
}

# destroy 是显式破坏性操作：必须符合当前适配器名称空间及 managed 标记。
cmd_destroy() {
  local session=${1:-} handle
  session=${session:-$(stable_session_name "$PWD")}
  case "$session" in
    "$ADAPTER_PREFIX"-*) ;;
    *)
      printf 'refusing to destroy session outside adapter namespace: %s\n' "$session" >&2
      exit 1
      ;;
  esac
  require_managed_session "$session"
  handle=$(require_session_handle "$session") || return 1
  tmux kill-session -t "$handle"
  printf 'destroyed session=%s\n' "$session"
}

# 使用 tmux bracketed paste 粘贴任意文本：-r 保留 LF，-p 将整段内容标记为一次粘贴，
# 避免多行消息被目标 TUI 按换行拆成多轮提交。
cmd_send() {
  local target=${1:?tmux target is required}
  shift
  local message
  local pane
  local buffer_name="tmux-agent-$$"

  require_target "$target"
  require_agent_pane "$target"
  require_target_session_contract "$target"
  pane=$(tmux display-message -p -t "$target" '#{pane_id}')

  if (($# > 0)); then
    message=$*
  else
    message=$(cat)
  fi
  if [[ -z "$message" ]]; then
    printf 'message must not be empty\n' >&2
    exit 1
  fi

  printf '%s' "$message" | tmux load-buffer -b "$buffer_name" -
  tmux paste-buffer -dpr -b "$buffer_name" -t "$pane"
  tmux send-keys -t "$pane" Enter
  printf 'sent to %s (%s chars)\n' "$target" "${#message}"
}

# Callback-only transport. Coordinates may change, but the original pane identity
# must still match at mutation time. The tmux server evaluates -F without a shell.
cmd_send_checked() {
  local pane=${1:?pane id is required} expected_pid=${2:?expected pid is required}
  local expected_native=${3?expected native id is required}
  shift 3
  local target message actual_command condition receipt buffer_name="tmux-agent-$$"
  if [[ ! "$pane" =~ ^%[0-9]+$ || ! "$expected_pid" =~ ^[0-9]+$ ]] ||
     { [[ -n "$expected_native" ]] && ! is_uuid "$expected_native"; }; then
    printf 'refusing invalid callback identity\n' >&2
    return 1
  fi
  target=$(target_from_pane "$pane") || return 1
  require_agent_pane "$pane"
  require_target_session_contract "$target"
  actual_command=$(tmux display-message -p -t "$pane" '#{pane_current_command}') || return 1
  if ! adapter_is_process "$actual_command" && ! pane_runs_cli "$pane"; then
    printf 'refusing changed callback foreground process: %s\n' "$pane" >&2
    return 1
  fi
  if (($# > 0)); then message=$*; else message=$(cat); fi
  if [[ -z "$message" ]]; then printf 'message must not be empty\n' >&2; return 1; fi
  # The only values inserted in command/format syntax are checked IDs and trusted
  # adapter process names. The message is data in an independent tmux buffer.
  printf '%s' "$message" | tmux load-buffer -b "$buffer_name" -
  condition="#{&&:#{==:#{pane_id},$pane},#{&&:#{==:#{pane_pid},$expected_pid},#{&&:#{==:#{@${ADAPTER_METADATA}_session_id},$expected_native},#{==:#{pane_current_command},$actual_command}}}}"
  if ! receipt=$(tmux if-shell -F -t "$pane" "$condition" \
    "paste-buffer -dpr -b $buffer_name -t $pane ; send-keys -t $pane Enter ; display-message -p TMUX_AGENT_SENT" \
    "delete-buffer -b $buffer_name ; display-message -p TMUX_AGENT_REFUSED"); then
    tmux delete-buffer -b "$buffer_name" 2>/dev/null || true
    printf 'callback send outcome unknown; do not resend\n' >&2
    return 3
  fi
  if [[ "$receipt" == TMUX_AGENT_REFUSED ]]; then
    printf 'refusing stale CLI callback identity: %s\n' "$pane" >&2
    return 1
  elif [[ "$receipt" != TMUX_AGENT_SENT ]]; then
    printf 'callback send receipt unknown; do not resend\n' >&2
    return 3
  fi
  printf 'sent to %s\n' "$pane"
}

# capture 只读历史；限制行数防止误取过大的 pane scrollback。
cmd_capture() {
  local target=${1:?tmux target is required}
  local lines=${2:-120}

  require_target "$target"
  if [[ ! "$lines" =~ ^[0-9]+$ ]] || ((lines < 1 || lines > 5000)); then
    printf 'history-lines must be an integer between 1 and 5000\n' >&2
    exit 1
  fi
  tmux capture-pane -p -J -t "$target" -S "-$lines"
}

cmd_status() {
  local target=${1:?tmux target is required}
  require_target "$target"
  tmux display-message -p -t "$target" "target=#{session_name}:#{window_index}.#{pane_index} command=#{pane_current_command} cwd=#{pane_current_path} active=#{pane_active} dead=#{pane_dead} pid=#{pane_pid} permission_mode=#{@${ADAPTER_METADATA}_permission_mode} native_session_id=#{@${ADAPTER_METADATA}_session_id}"
}

# Capture a callback address while the original pane and project are known.
# The receiver checks this snapshot again; a recycled pane is not the sender.
target_from_pane() {
  local pane=$1 actual
  [[ "$pane" =~ ^%[0-9]+$ ]] || return 1
  actual=$(tmux display-message -p -t "$pane" '#{pane_id}') || return 1
  if [[ "$actual" != "$pane" ]]; then
    printf 'refusing non-exact pane id: %s\n' "$pane" >&2
    return 1
  fi
  tmux display-message -p -t "$pane" '#{session_name}:#{window_index}.#{pane_index}'
}

cmd_address() {
  local target=${1:?tmux target is required} root pane pid native_id session
  require_command python3
  if [[ "$target" =~ ^%[0-9]+$ ]]; then
    pane=$target
    target=$(target_from_pane "$pane") || return 1
  else
    require_target "$target"
    pane=$(tmux display-message -p -t "$target" '#{pane_id}') || return 1
  fi
  require_target "$target"
  require_agent_pane "$pane"
  require_target_session_contract "$target"
  root=$(project_root "$PWD")
  target=$(target_from_pane "$pane") || return 1
  pid=$(tmux display-message -p -t "$pane" '#{pane_pid}') || return 1
  session=$(tmux display-message -p -t "$pane" '#{session_name}') || return 1
  native_id=$(session_option "$session" session_id)
  python3 -c 'import json,sys; print(json.dumps(dict(zip(
    ["kind","target","cwd","pane_id","pane_pid","native_session_id"], sys.argv[1:])), ensure_ascii=False))' \
    "$AGENT-cli" "$target" "$root" "$pane" "$pid" "$native_id"
}

main() {
  # Pure name formatting and help must work without a tmux installation.
  case "${1:-}" in
    name|format-name|-h|--help|help|"") ;;
    *) require_command tmux ;;
  esac
  case "${1:-}" in
    list)
      shift
      cmd_list "$@"
      ;;
    name)
      shift
      cmd_name "$@"
      ;;
    format-name)
      shift
      cmd_format_name "$@"
      ;;
    start)
      shift
      cmd_start "$@"
      ;;
    target)
      shift
      cmd_target "$@"
      ;;
    attach)
      shift
      cmd_attach "$@"
      ;;
    destroy)
      shift
      cmd_destroy "$@"
      ;;
    send)
      shift
      cmd_send "$@"
      ;;
    send-checked)
      shift
      cmd_send_checked "$@"
      ;;
    capture)
      shift
      cmd_capture "$@"
      ;;
    status)
      shift
      cmd_status "$@"
      ;;
    address)
      shift
      cmd_address "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}
