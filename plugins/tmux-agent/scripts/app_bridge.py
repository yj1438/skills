#!/usr/bin/env python3
"""Local Code-session discovery and one-shot delivery. Python 3.10+, stdlib only."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import socket
import stat
import struct
import subprocess
import sys
import time
from urllib.parse import parse_qs, urlparse
import uuid

HELPER = Path(__file__).resolve().with_name("tmux-agent.sh")
KINDS = {"claude-cli", "codex-cli", "claude-app", "codex-app"}
DESKTOP_ENTRIES = {"claude-desktop", "claude-desktop-3p"}
MAX_BODY = 64 * 1024
MAX_WIRE = 128 * 1024
START = "[TMUX_AGENT_MESSAGE_V1]"
END = "[/TMUX_AGENT_MESSAGE_V1]"


class BridgeError(Exception):
    def __init__(self, message, *, status="failed", details=None):
        super().__init__(message)
        self.status, self.details = status, details


class RPCResponseError(BridgeError):
    """A server response, distinguished from a lost/invalid transport response."""


def emit(value):
    print(json.dumps(value, ensure_ascii=False))


def canonical_id(value):
    try:
        result = str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        raise BridgeError("expected a session UUID") from None
    if value.lower() != result:
        raise BridgeError("expected a canonical session UUID")
    return result


def target_id(value):
    if value.startswith("codex://"):
        url = urlparse(value)
        query = parse_qs(url.query, keep_blank_values=True)
        if (url.netloc != "threads" or url.fragment or
                set(query) - {"hostId"} or query.get("hostId", ["local"]) != ["local"]):
            raise BridgeError("only local codex://threads/<UUID> links are supported")
        return canonical_id(url.path.removeprefix("/"))
    try:
        return canonical_id(value)
    except BridgeError:
        if "://" in value or not value.strip() or any(ord(c) < 32 for c in value):
            raise BridgeError("expected an exact title, UUID, or local Codex thread link")
        return value


def binary(name):
    found = shutil.which(name)
    if not found:
        raise BridgeError(f"Required command not found: {name}")
    return found


class CodexRPC:
    """Owns a short-lived metadata client, never resumes an existing thread."""
    def __init__(self, timeout):
        self.timeout = timeout
        self.buffer = b""
        self.number = 0
        self.process = subprocess.Popen(
            [binary("codex"), "app-server", "--stdio"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            self.call("initialize", {"clientInfo": {"name": "tmux_agent", "version": "2.1.1"}})
            self.write({"method": "initialized", "params": {}})
        except BaseException:
            self.close()
            raise

    def write(self, value):
        try:
            self.process.stdin.write((json.dumps(value) + "\n").encode())
            self.process.stdin.flush()
        except (OSError, BrokenPipeError):
            raise BridgeError("Codex App Server connection closed") from None

    def call(self, method, params):
        self.number += 1
        request_id = self.number
        self.write({"id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + self.timeout
        while True:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                try:
                    value = json.loads(line)
                except (ValueError, UnicodeError):
                    raise BridgeError("invalid JSON from Codex App Server") from None
                if not isinstance(value, dict):
                    raise BridgeError("invalid Codex App Server frame")
                if value.get("id") != request_id:
                    continue
                if "error" in value:
                    raise RPCResponseError(f"Codex {method} failed", details=value["error"])
                if not isinstance(value.get("result"), dict):
                    raise BridgeError(f"invalid Codex {method} result")
                return value["result"]
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise BridgeError(f"Codex {method} timed out")
            if not self.selector.select(remaining):
                continue
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise BridgeError(f"Codex App Server exited during {method}")
            self.buffer += chunk
            if len(self.buffer) > 8 * 1024 * 1024:
                raise BridgeError("Codex App Server response exceeded the size limit")

    def close(self):
        self.selector.close()
        if self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
                self.process.wait(timeout=2)
            except ProcessLookupError:
                pass
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait()
        for pipe in (self.process.stdin, self.process.stdout):
            pipe.close()

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()


def codex_threads(timeout):
    rows, cursor, seen = [], None, set()
    with CodexRPC(timeout) as rpc:
        for _ in range(100):
            params = {"limit": 100, "sortKey": "updated_at", "sortDirection": "desc", "archived": False}
            if cursor:
                params["cursor"] = cursor
            page = rpc.call("thread/list", params)
            data = page.get("data")
            if not isinstance(data, list):
                raise BridgeError("invalid thread/list data")
            for row in data:
                if not isinstance(row, dict):
                    raise BridgeError("invalid thread/list row")
                rows.append({"kind": "codex-app", "target": canonical_id(row.get("id")),
                             "title": row.get("name") or "", "cwd": row.get("cwd"),
                             "source": row.get("source"), "updated_at": row.get("updatedAt"),
                             "availability": "stored-local", "runtime_status": "unknown"})
            cursor = page.get("nextCursor")
            if not cursor:
                return rows
            if not isinstance(cursor, str) or cursor in seen:
                raise BridgeError("invalid or repeated Codex pagination cursor")
            seen.add(cursor)
    raise BridgeError("thread list exceeded 100 pages; refine the target before sending")


def private_file(path, *, is_socket=False):
    try:
        info = path.lstat()
    except OSError as error:
        raise BridgeError(f"unavailable local endpoint: {error.strerror}") from None
    expected = stat.S_ISSOCK(info.st_mode) if is_socket else stat.S_ISREG(info.st_mode)
    if not expected or info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise BridgeError("refusing unowned, writable, symlinked, or wrong-type endpoint")
    parent = path.parent.resolve()
    for directory in (parent, *parent.parents):
        info = directory.stat()
        if info.st_uid not in {0, os.getuid()} or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
            raise BridgeError("refusing an endpoint in an unsafe parent directory")


def process_start(pid):
    try:
        result = subprocess.run(["ps", "-p", str(pid), "-o", "lstart="],
                                text=True, capture_output=True, timeout=3,
                                env=dict(os.environ, LC_ALL="C", TZ="UTC"))
    except (OSError, subprocess.TimeoutExpired):
        return None
    return " ".join(result.stdout.split()) if result.returncode == 0 else None


def claude_threads(claude_dir):
    if sys.platform not in {"darwin", "linux"}:
        raise BridgeError("Claude inbox currently supports local macOS/Linux Code sessions only")
    directory = claude_dir / "sessions"
    if not directory.exists():
        return []
    if directory.is_symlink() or directory.stat().st_uid != os.getuid() or directory.stat().st_mode & 0o022:
        raise BridgeError("refusing unsafe Claude session registry")
    rows = []
    for path in sorted(directory.glob("*.json")):
        # Stale registrations are not targets. Never discover by newest transcript.
        try:
            private_file(path)
            if path.stat().st_size > 65536:
                continue
            row = json.loads(path.read_text())
            if row.get("entrypoint") not in DESKTOP_ENTRIES or row.get("peerProtocol") != 1:
                continue
            pid = row.get("pid")
            if type(pid) is not int or pid <= 0 or path.stem != str(pid):
                continue
            stamp = process_start(pid)
            if not stamp or stamp != " ".join(str(row.get("procStart", "")).split()):
                continue
            target = canonical_id(row.get("sessionId"))
            inbox = Path(row.get("messagingSocketPath", ""))
            if not inbox.is_absolute():
                continue
            private_file(inbox, is_socket=True)
            rows.append({"kind": "claude-app", "target": target, "title": row.get("name") or "",
                         "cwd": row.get("cwd"), "pid": pid, "proc_start": stamp,
                         "socket": str(inbox), "entrypoint": row["entrypoint"],
                         "version": row.get("version"), "status": row.get("status"),
                         "updated_at": row.get("updatedAt")})
        except (OSError, ValueError, TypeError, AttributeError, BridgeError):
            continue
    return rows


def resolve(rows, target):
    target = target_id(target)
    # IDs take precedence over another session's title, including UUID-like titles.
    matches = [r for r in rows if r["target"] == target]
    if not matches:
        matches = [r for r in rows if r["title"] == target]
    if len(matches) != 1:
        raise BridgeError("target not found" if not matches else "ambiguous target; ask the user to select a UUID",
                          details={"candidates": matches})
    return matches[0]


def check_address(value):
    if not isinstance(value, dict) or value.get("kind") not in KINDS:
        raise BridgeError("invalid endpoint kind")
    if not isinstance(value.get("target"), str) or not value["target"]:
        raise BridgeError("missing exact endpoint target")
    if value["kind"].endswith("-app"):
        canonical_id(value["target"])
    else:
        for key in ["cwd", "pane_id", "pane_pid", "native_session_id"]:
            if not isinstance(value.get(key), str):
                raise BridgeError(f"CLI callback address missing {key}; obtain it with Helper address")
        if not Path(value["cwd"]).is_absolute():
            raise BridgeError("CLI callback cwd must be absolute")
        if not re.fullmatch(r".+:\d+\.\d+", value["target"]):
            raise BridgeError("CLI callback needs an exact session:window.pane")
        if not re.fullmatch(r"%\d+", value["pane_id"]) or not value["pane_pid"].isdigit():
            raise BridgeError("invalid CLI identity snapshot")
    if value["kind"] == "claude-app":
        if (type(value.get("pid")) is not int or value["pid"] <= 0 or
                not isinstance(value.get("socket"), str) or not Path(value["socket"]).is_absolute() or
                not isinstance(value.get("proc_start"), str) or not value["proc_start"]):
            raise BridgeError("Claude callback needs an absolute socket and exact PID/start identity")
    return value


def load_json(value):
    try:
        return json.loads(value)
    except (ValueError, TypeError):
        raise BridgeError("invalid JSON argument") from None


def body(args):
    value = args.message if args.message is not None else sys.stdin.read(MAX_BODY + 1)
    if not value.strip() or len(value.encode()) > MAX_BODY or "\x00" in value:
        raise BridgeError("message must be nonempty UTF-8 text without NUL, at most 64 KiB")
    return value


def envelope(kind, to, reply_to, text, request_id=None):
    return {"protocol": "tmux-agent/1", "kind": kind,
            "request_id": canonical_id(request_id) if request_id else str(uuid.uuid4()),
            "to": check_address(to), "reply_to": check_address(reply_to) if reply_to else None,
            "body": text}


def render(message):
    metadata = {k: v for k, v in message.items() if k != "body"}
    content = START + "\n" + json.dumps(metadata, ensure_ascii=False) + "\n" + END + "\n\n" + message["body"]
    if message["kind"] == "request":
        content += ("\n\n这是用户授权的一次 Code 会话协作。直接处理本任务，遵守任务原有权限与修改范围，不再委派。"
                    "完成后保留完整可见结果；reply_to 非空时按其准确地址回信一次，使用相同 request_id 和 kind=result。"
                    "按接收方的 tmux-agent 技能执行回信；未加载时可阅读本次调用的 Skill：" +
                    str(HELPER.parents[1] / "SKILL.md") +
                    "。CLI 回信前先在原 cwd capture 确认空闲；等待确认或忙碌时暂不发送。"
                    "不修改权限/配置，不回复隐藏思考，不把传输成功称为任务完成。")
    else:
        content += "\n\n这是上述 request_id 的最终结果。接收并呈现结果即可，不再次委派、不自动回信。"
    if len(content.encode()) > MAX_WIRE:
        raise BridgeError("encoded message exceeds 128 KiB")
    return content


def queue_codex(endpoint, content, timeout):
    try:
        result = subprocess.run([binary("codex"), "queue", "--thread", endpoint["target"],
                                 "--message", content], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise BridgeError("queue timed out; delivery is unknown, do not resend", status="unknown") from None
    except OSError as error:
        raise BridgeError(f"could not invoke queue: {error.strerror}") from None
    if result.returncode:
        raise BridgeError("queue failed; it may have submitted the message, do not resend",
                          status="unknown", details={"exit_code": result.returncode,
                                                     "stderr": result.stderr[-2000:]})
    pattern = r"Queued message ([0-9a-fA-F-]{36}) for thread ([0-9a-fA-F-]{36})\."
    match = re.fullmatch(pattern, result.stdout.strip())
    if not match:
        raise BridgeError("unrecognized queue receipt; do not resend", status="unknown")
    try:
        message_id = canonical_id(match[1])
        thread_id = canonical_id(match[2])
    except BridgeError:
        raise BridgeError("unrecognized queue receipt; do not resend", status="unknown") from None
    if thread_id != endpoint["target"]:
        raise BridgeError("unrecognized queue receipt; do not resend", status="unknown")
    return {"status": "queued", "queue_message_id": message_id}


def open_codex(endpoint, timeout):
    """Opening an exact deep link may wake queued work; it is not delivery proof."""
    command = "open" if sys.platform == "darwin" else "xdg-open"
    try:
        result = subprocess.run([binary(command), "codex://threads/" + endpoint["target"]],
                                capture_output=True, text=True, timeout=timeout)
    except (BridgeError, OSError, subprocess.TimeoutExpired) as error:
        return {"open_requested": False, "open_warning": str(error)}
    return {"open_requested": result.returncode == 0,
            "open_warning": None if result.returncode == 0 else result.stderr[-500:]}


def peer_pid(connection):
    if sys.platform == "linux":
        return struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[0]
    if sys.platform == "darwin":
        # Darwin sys/un.h: SOL_LOCAL=0, LOCAL_PEERPID=2.
        return struct.unpack("i", connection.getsockopt(0, 2, 4))[0]
    raise BridgeError("peer process verification is unavailable on this platform")


def send_claude(endpoint, content, timeout):
    private_file(Path(endpoint["socket"]), is_socket=True)
    if process_start(endpoint["pid"]) != endpoint["proc_start"]:
        raise BridgeError("refusing stale Claude process identity")
    frame = {"type": "user", "session_id": endpoint["target"], "uuid": str(uuid.uuid4()),
             "msg_id": str(uuid.uuid4()), "priority": "next", "from": "tmux-agent",
             "message": {"role": "user", "content": content}}
    wire = (json.dumps(frame, ensure_ascii=False) + "\n").encode()
    if len(wire) > MAX_WIRE:
        raise BridgeError("Claude wire frame exceeds 128 KiB")
    wrote = False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout)
            connection.connect(endpoint["socket"])
            if peer_pid(connection) != endpoint["pid"]:
                raise BridgeError("refusing Claude socket peer PID mismatch")
            wrote = True  # sendall may partially write before raising.
            connection.sendall(wire)
            connection.shutdown(socket.SHUT_WR)
    except OSError as error:
        raise BridgeError(f"Claude inbox write failed: {error.strerror}; do not resend",
                          status="unknown" if wrote else "failed") from None
    # No synchronous delivery acknowledgement is provided by this socket protocol.
    return {"status": "submitted", "delivery": "unconfirmed", "message_id": frame["msg_id"]}


def cli_call(endpoint, command, *args, timeout=10):
    agent = endpoint["kind"].removesuffix("-cli")
    selector = endpoint["pane_id"] if command in {"address", "send-checked"} else endpoint["target"]
    try:
        result = subprocess.run(["bash", str(HELPER), agent, command, selector, *args],
                                cwd=endpoint["cwd"], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise BridgeError(f"CLI {command} timed out; do not resend", status="unknown") from None
    if result.returncode:
        raise BridgeError(f"CLI {command} failed", status="unknown" if result.returncode == 3 else "failed",
                          details={"stderr": result.stderr.strip()})
    return result.stdout


def deliver(endpoint, message, args):
    content = render(message)
    if endpoint["kind"].endswith("-cli"):
        current = load_json(cli_call(endpoint, "address", timeout=args.timeout))
        identity_keys = ("kind", "cwd", "pane_id", "pane_pid", "native_session_id")
        if any(current.get(key) != endpoint.get(key) for key in identity_keys):
            raise BridgeError("refusing stale CLI callback address", details={"current": current})
        if not args.confirm_idle:
            raise BridgeError("capture the exact CLI pane, confirm it is idle, then use --confirm-idle",
                              status="pending", details={"address": current})
        cli_call(endpoint, "send-checked", endpoint["pane_pid"], endpoint["native_session_id"],
                 content, timeout=args.timeout)
        return {"status": "submitted", "delivery": "unconfirmed"}
    rows = discover(endpoint["kind"], args)
    current = resolve(rows, endpoint["target"])
    if endpoint["kind"] == "claude-app":
        for key in ["socket", "pid", "proc_start"]:
            if current[key] != endpoint.get(key):
                raise BridgeError("refusing stale Claude callback address")
        return send_claude(current, content, args.timeout)
    receipt = queue_codex(current, content, args.timeout)
    if args.open_app:
        receipt.update(open_codex(current, args.timeout))
    return receipt


def discover(kind, args):
    return codex_threads(args.timeout) if kind == "codex-app" else claude_threads(args.claude_dir)


def parse_envelope(value):
    if value.startswith(START + "\n"):
        try:
            value = value.split("\n", 1)[1].split("\n" + END, 1)[0]
        except IndexError:
            raise BridgeError("invalid request envelope") from None
    request = load_json(value)
    if not isinstance(request, dict) or request.get("protocol") != "tmux-agent/1" or request.get("kind") != "request":
        raise BridgeError("reply accepts a request envelope only; never reply to a result")
    canonical_id(request.get("request_id"))
    check_address(request.get("to"))
    check_address(request.get("reply_to"))
    return request


def main():
    if sys.version_info < (3, 10):
        raise BridgeError("App bridge requires Python 3.10 or newer")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("route", choices=["codex-app", "claude-app", "reply"])
    parser.add_argument("command", nargs="?", choices=["list", "resolve", "address", "send", "create"])
    parser.add_argument("target", nargs="?", help="exact UUID, title, or local Codex link")
    parser.add_argument("--search", default="")
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("--limit", type=int, default=30)
    parser.add_argument("--title")
    parser.add_argument("--message", help="omit to read message text from stdin")
    parser.add_argument("--reply-to", help="JSON address from Helper address")
    parser.add_argument("--no-reply", action="store_true")
    parser.add_argument("--envelope", help="request metadata JSON, or rendered request")
    parser.add_argument("--request-id")
    parser.add_argument("--confirm-idle", action="store_true", help="CLI callback only, after capture verification")
    parser.add_argument("--open", dest="open_app", action="store_true",
                        help="after successful Codex queue, ask the OS to open the exact App thread")
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--claude-dir", type=Path, default=Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude"))))
    args = parser.parse_args()
    if not 0 < args.timeout <= 60 or not 1 <= args.limit <= 1000:
        raise BridgeError("timeout must be in (0,60], limit in [1,1000]")
    if args.route == "reply":
        if args.open_app:
            raise BridgeError("--open is only supported by codex-app send")
        if not args.envelope or args.command or args.target:
            raise BridgeError("reply requires --envelope and message text")
        request = parse_envelope(args.envelope)
        result = envelope("result", request["reply_to"], None, body(args), request["request_id"])
        receipt = deliver(result["to"], result, args)
        emit({"request_id": result["request_id"], "kind": "result", "to": result["to"], **receipt})
        return
    if args.command is None:
        raise BridgeError("choose list, resolve, address, send, or create")
    if args.open_app and (args.route != "codex-app" or args.command != "send"):
        raise BridgeError("--open is only supported by codex-app send")
    if args.command == "create":
        if args.route != "codex-app":
            raise BridgeError("create the Code session in Claude Desktop, then list and select its exact ID; no supported headless Desktop creation API")
        if not args.cwd or not args.cwd.is_dir():
            raise BridgeError("create requires an existing --cwd directory")
        with CodexRPC(args.timeout) as rpc:
            try:
                created = rpc.call("thread/start", {"cwd": str(args.cwd.resolve())})
                thread = created.get("thread", {})
                thread_id = canonical_id(thread.get("id"))
            except RPCResponseError as error:
                # JSON-RPC protocol validation errors cannot have run thread/start.
                # Internal/business errors may follow partial creation: stay unknown.
                code = error.details.get("code") if isinstance(error.details, dict) else None
                if code in {-32700, -32600, -32601, -32602}:
                    raise
                raise BridgeError("create outcome is unknown; inspect the thread list before creating again",
                                  status="unknown", details=error.details) from None
            except BridgeError as error:
                raise BridgeError("create outcome is unknown; inspect the thread list before creating again",
                                  status="unknown", details=str(error)) from None
            warning = None
            if args.title:
                try:
                    rpc.call("thread/name/set", {"threadId": thread_id, "name": args.title})
                except BridgeError as error:
                    warning = str(error)
            emit({"status": "created", "kind": "codex-app", "target": thread_id,
                  "ui_opened": False, "warning": warning})
        return
    rows = discover(args.route, args)
    if args.command == "list":
        matches = [r for r in rows if args.search in r["title"] and
                   (not args.cwd or r.get("cwd") == str(args.cwd.resolve()))]
        emit({"sessions": matches[:args.limit], "matches": len(matches),
              "truncated": len(matches) > args.limit,
              "scope": "stored-local-threads" if args.route == "codex-app" else "live-desktop-code"})
        return
    if not args.target:
        raise BridgeError("select an exact target first; use list when the user has not selected a session")
    endpoint = resolve(rows, args.target)
    if args.command in {"resolve", "address"}:
        emit(endpoint)
        return
    if args.no_reply == bool(args.reply_to):
        raise BridgeError("send requires exactly one of --reply-to JSON or --no-reply")
    reply_to = check_address(load_json(args.reply_to)) if args.reply_to else None
    message = envelope("request", endpoint, reply_to, body(args), args.request_id)
    receipt = deliver(endpoint, message, args)
    emit({"request_id": message["request_id"], "kind": "request", "envelope":
          {k: v for k, v in message.items() if k != "body"}, **receipt})


if __name__ == "__main__":
    try:
        main()
    except BridgeError as error:
        emit({"status": error.status, "error": str(error), "details": error.details})
        sys.exit({"unknown": 3, "pending": 4}.get(error.status, 1))
    except (OSError, ValueError, TypeError, KeyError) as error:
        emit({"status": "failed", "error": str(error)})
        sys.exit(1)
