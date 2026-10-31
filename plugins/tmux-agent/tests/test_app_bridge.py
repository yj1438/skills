#!/usr/bin/env python3
"""Isolated App Server/queue shims and real Unix sockets; no model or user sessions."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
spec = importlib.util.spec_from_file_location("app_bridge", SCRIPTS / "app_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
CODEX = "11111111-1111-4111-8111-111111111111"
OTHER = "22222222-2222-4222-8222-222222222222"
CLAUDE = "33333333-3333-4333-8333-333333333333"
REQUEST = "44444444-4444-4444-8444-444444444444"
QUEUE = "55555555-5555-4555-8555-555555555555"

FAKE_CODEX = r'''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
with open(os.environ['APP_TEST_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\n')
mode=os.environ.get('APP_TEST_MODE','ok')
if sys.argv[1]=='queue':
 if mode=='timeout': time.sleep(6)
 if mode=='error': sys.exit(7)
 target=sys.argv[sys.argv.index('--thread')+1]
 if mode=='bad_receipt': print('queue changed format'); sys.exit(0)
 if mode=='wrong_target': target='22222222-2222-4222-8222-222222222222'
 message_id='a'*36 if mode=='invalid_queue_id' else '55555555-5555-4555-8555-555555555555'
 if mode=='invalid_target_id': target='a'*36
 print('Queued message '+message_id+' for thread '+target+'.')
 sys.exit(0)
assert sys.argv[1:]==['app-server','--stdio']
for line in sys.stdin:
 q=json.loads(line)
 if 'id' not in q: continue
 method=q['method']
 with open(os.environ['APP_TEST_LOG'],'a') as f: f.write(json.dumps(q)+'\n')
 if mode=='bad_rpc': print('[]',flush=True); continue
 if method=='initialize': result={}
 elif method=='thread/list':
  i=bool(q['params'].get('cursor'))
  rows=[{'id':'11111111-1111-4111-8111-111111111111','name':'工作会话','cwd':'/project one','source':'vscode','updatedAt':20},
        {'id':'22222222-2222-4222-8222-222222222222','name':'另一个会话','cwd':'/project two','source':'vscode','updatedAt':10}]
  if mode=='duplicate': rows[1]['name']=rows[0]['name']
  if mode=='uuid_title': rows[1]['name']=rows[0]['id']
  result={'data':[rows[int(i)]],'nextCursor':None if i else 'page-two'}
  if mode=='repeat_cursor': result['nextCursor']='page-two'
 elif method=='thread/start':
  if mode=='create_lost_ack': sys.exit(0)
  if mode in ('invalid_params','internal_error'):
   code=-32602 if mode=='invalid_params' else -32603
   print(json.dumps({'id':q['id'],'error':{'code':code,'message':mode,'data':{'preserved':True}}}),flush=True); continue
  result={'thread':{'id':'11111111-1111-4111-8111-111111111111'}}
 elif method=='thread/name/set':
  if mode=='rename_error':
   print(json.dumps({'id':q['id'],'error':{'code':-1,'message':'rename failed'}}),flush=True); continue
  result={}
 else: raise AssertionError(method)
 print(json.dumps({'method':'test/notification','params':{}}),flush=True)
 print(json.dumps({'id':q['id'],'result':result}),flush=True)
'''


class AppBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="tab-", dir="/tmp")
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.registry = self.home / ".claude/sessions"
        self.registry.mkdir(parents=True)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        (self.bin / "python3").symlink_to(sys.executable)
        (self.bin / "codex").write_text(FAKE_CODEX)
        (self.bin / "codex").chmod(0o755)
        for opener in ["open", "xdg-open"]:
            path = self.bin / opener
            path.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                            'from pathlib import Path\n'
                            'Path(os.environ["APP_TEST_LOG"]+".open").write_text(json.dumps(sys.argv[1:]))\n'
                            'sys.exit(1 if os.environ.get("APP_TEST_MODE")=="open_error" else 0)\n')
            path.chmod(0o755)
        self.log = self.base / "calls.jsonl"
        self.env = {"PATH": str(self.bin) + os.pathsep + os.defpath, "HOME": str(self.home),
                    "APP_TEST_LOG": str(self.log), "TERM": "xterm-256color"}
        self.server = None
        self.listener = None
        self.frames = []
        self.finished = threading.Event()

    def tearDown(self):
        self.finished.set()
        if self.listener:
            self.listener.close()
        if self.server:
            self.server.join(timeout=2)
        self.tmp.cleanup()

    def run_helper(self, *args, data=None, mode="ok", ok=True):
        result = subprocess.run(["bash", str(SCRIPTS / "tmux-agent.sh"), *args],
                                input=data, text=True, capture_output=True, cwd=self.base,
                                env=dict(self.env, APP_TEST_MODE=mode), timeout=15)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result, json.loads(result.stdout)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def queue_calls(self):
        return [q for q in self.calls() if isinstance(q, list) and q[0] == "queue"]

    def listen(self, *, entrypoint="claude-desktop", stamp=None, session=CLAUDE):
        path = self.base / "inbox.sock"
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(path))
        self.listener.listen()
        self.listener.settimeout(0.1)
        def receive():
            try:
                while not self.finished.is_set():
                    try:
                        connection, _ = self.listener.accept()
                        break
                    except socket.timeout:
                        continue
                else:
                    return
                with connection:
                    data = b""
                    while True:
                        part = connection.recv(65536)
                        if not part:
                            break
                        data += part
                    self.frames.extend(json.loads(x) for x in data.splitlines() if x)
            except (OSError, ValueError):
                pass
            finally:
                self.finished.set()
        self.server = threading.Thread(target=receive, daemon=True)
        self.server.start()
        row = {"sessionId": session, "pid": os.getpid(), "entrypoint": entrypoint,
               "procStart": stamp or self.native_start(os.getpid()), "peerProtocol": 1,
               "messagingSocketPath": str(path), "name": "桌面测试", "cwd": str(self.base),
               "version": "2.1.293", "status": "idle", "updatedAt": 1}
        (self.registry / f"{os.getpid()}.json").write_text(json.dumps(row))
        return row

    @staticmethod
    def native_start(pid):
        # Construct the native registry independently of the implementation under test.
        value = subprocess.check_output(['ps', '-p', str(pid), '-o', 'lstart='],
                                        text=True, env=dict(os.environ, LC_ALL='C', TZ='UTC'))
        return ' '.join(value.split())

    def test_native_utc_registry_works_from_non_utc_environments(self):
        self.listen()
        for timezone in ['UTC', 'Asia/Shanghai', 'America/Los_Angeles']:
            self.env.update(TZ=timezone, LC_ALL='POSIX')
            _, result = self.run_helper('claude-app', 'list')
            self.assertEqual([r['target'] for r in result['sessions']], [CLAUDE])
        self.env['TZ'] = 'Asia/Shanghai'
        _, result = self.run_helper('claude-app', 'send', CLAUDE, '--no-reply', '--message', 'timezone reply')
        self.assertEqual(result['status'], 'submitted')
        self.assertTrue(self.finished.wait(2))
        self.assertEqual(len(self.frames), 1)

    def test_python_version_guard_runs_before_discovery_or_delivery(self):
        with patch.object(bridge.sys, 'version_info', (3, 8, 0)), patch.object(bridge, 'CodexRPC') as rpc:
            with self.assertRaisesRegex(bridge.BridgeError, 'Python 3.10'):
                bridge.main()
            rpc.assert_not_called()

    def test_explicit_unsupported_interpreter_has_structured_error_and_no_side_effects(self):
        bad = self.bin / 'old-python'
        bad.write_text('#!/bin/sh\nexit 1\n')
        bad.chmod(0o755)
        self.env['TMUX_AGENT_PYTHON'] = str(bad)
        _, result = self.run_helper('codex-app', 'list', ok=False)
        self.assertIn('Python 3.10', result['error'])
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(self.calls(), [])

    def test_uuid_or_deep_link_takes_precedence_over_another_title(self):
        for target in [CODEX, 'codex://threads/' + CODEX]:
            _, result = self.run_helper('codex-app', 'resolve', target, mode='uuid_title')
            self.assertEqual(result['target'], CODEX)

    def test_codex_list_is_paginated_and_metadata_only(self):
        _, result = self.run_helper("codex-app", "list")
        self.assertEqual([s["target"] for s in result["sessions"]], [CODEX, OTHER])
        self.assertEqual(result["sessions"][0]["runtime_status"], "unknown")
        methods = [q["method"] for q in self.calls() if isinstance(q, dict)]
        self.assertEqual(methods, ["initialize", "thread/list", "thread/list"])
        self.assertEqual(self.queue_calls(), [])

    def test_filter_and_truncation_do_not_hide_ambiguity(self):
        _, result = self.run_helper("codex-app", "list", "--search", "会话", "--limit", "1")
        self.assertTrue(result["truncated"])
        self.assertEqual(result["matches"], 2)
        _, result = self.run_helper("codex-app", "send", "工作会话", "--no-reply", "--message", "hello",
                                    mode="duplicate", ok=False)
        self.assertIn("ambiguous", result["error"])
        self.assertEqual(len(result["details"]["candidates"]), 2)
        self.assertEqual(self.queue_calls(), [])

    def test_missing_target_and_repeated_cursor_never_send(self):
        self.run_helper("codex-app", "send", OTHER[:-1] + "9", "--message", "hello", "--no-reply", ok=False)
        self.run_helper("codex-app", "resolve", CODEX, mode="repeat_cursor", ok=False)
        self.assertEqual(self.queue_calls(), [])

    def test_resolve_exact_title_or_local_link(self):
        for target in [CODEX, "工作会话", "codex://threads/" + CODEX + "?hostId=local"]:
            _, result = self.run_helper("codex-app", "address", target)
            self.assertEqual(result["target"], CODEX)
        self.run_helper("codex-app", "resolve", "codex://threads/" + CODEX + "?hostId=remote", ok=False)

    def test_multiline_unicode_and_shell_text_are_single_argv_data(self):
        message = '第一行\n$(touch NEVER) `echo no` % : "引号"\n末行\n'
        _, result = self.run_helper("codex-app", "send", CODEX, "--no-reply", data=message)
        self.assertEqual(result["status"], "queued")
        self.assertEqual(result["queue_message_id"], QUEUE)
        calls = self.queue_calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1:3], ["--thread", CODEX])
        self.assertIn(message, calls[0][-1])
        self.assertFalse((self.base / "NEVER").exists())
        self.assertNotIn("completed", result.values())

    def test_unknown_queue_receipt_timeout_or_exit_never_retries(self):
        for mode in ["bad_receipt", "wrong_target", "timeout", "error"]:
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                result, value = self.run_helper("codex-app", "send", CODEX, "--no-reply", "--message", "hello",
                                                 "--timeout", "5", mode=mode, ok=False)
                self.assertEqual(result.returncode, 3, value)
                self.assertEqual(value["status"], "unknown")
                self.assertEqual(len(self.queue_calls()), 1)

    def test_invalid_queue_receipt_uuids_are_unknown_without_retry_or_open(self):
        for mode in ["invalid_queue_id", "invalid_target_id"]:
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                result, value = self.run_helper("codex-app", "send", CODEX, "--no-reply",
                                                 "--message", "hello", "--open", mode=mode, ok=False)
                self.assertEqual(result.returncode, 3, value)
                self.assertEqual(value["status"], "unknown")
                self.assertIn("do not resend", value["error"])
                self.assertNotIn("queue_message_id", value)
                self.assertEqual(len(self.queue_calls()), 1)
                self.assertFalse(Path(str(self.log) + ".open").exists())

    def test_explicit_open_uses_exact_deep_link_and_preserves_queue_receipt(self):
        _, result = self.run_helper("codex-app", "send", CODEX, "--no-reply", "--message", "hello", "--open",
                                    mode="open_error")
        self.assertEqual(result["status"], "queued")
        self.assertFalse(result["open_requested"])
        self.assertEqual(json.loads(Path(str(self.log) + ".open").read_text()), ["codex://threads/" + CODEX])
        self.assertEqual(len(self.queue_calls()), 1)

    def test_reject_empty_large_or_nul_message_before_queue(self):
        for message in [" \n", "中" * 23000, "abc\0def"]:
            self.run_helper("codex-app", "send", CODEX, "--no-reply", data=message, ok=False)
        self.assertEqual(self.queue_calls(), [])

    def test_send_requires_explicit_feedback_mode(self):
        self.run_helper("codex-app", "send", CODEX, "--message", "hello", ok=False)
        self.run_helper("codex-app", "send", CODEX, "--no-reply", "--reply-to", '{}', "--message", "hello", ok=False)
        self.assertEqual(self.queue_calls(), [])

    def test_codex_create_no_turn_and_partial_rename_retains_id(self):
        _, result = self.run_helper("codex-app", "create", "--cwd", str(self.base), "--title", "新任务",
                                    mode="rename_error")
        self.assertEqual(result["status"], "created")
        self.assertEqual(result["target"], CODEX)
        self.assertFalse(result["ui_opened"])
        self.assertTrue(result["warning"])
        methods = [q["method"] for q in self.calls() if isinstance(q, dict)]
        self.assertEqual(methods, ["initialize", "thread/start", "thread/name/set"])
        self.assertEqual(self.queue_calls(), [])

    def test_claude_creation_does_not_fallback_to_cli(self):
        _, result = self.run_helper("claude-app", "create", "--cwd", str(self.base), ok=False)
        self.assertIn("Claude Desktop", result["error"])
        self.assertEqual(self.calls(), [])

    def test_lost_creation_receipt_does_not_create_again(self):
        result, value = self.run_helper("codex-app", "create", "--cwd", str(self.base),
                                         mode="create_lost_ack", ok=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(value["status"], "unknown")
        calls = [q for q in self.calls() if isinstance(q, dict) and q["method"] == "thread/start"]
        self.assertEqual(len(calls), 1)

    def test_creation_protocol_rejection_is_failed_but_internal_error_stays_unknown(self):
        for mode, status, exit_code in [('invalid_params', 'failed', 1), ('internal_error', 'unknown', 3)]:
            self.log.unlink(missing_ok=True)
            result, value = self.run_helper('codex-app', 'create', '--cwd', str(self.base), mode=mode, ok=False)
            self.assertEqual(result.returncode, exit_code)
            self.assertEqual(value['status'], status)
            self.assertTrue(value['details']['data']['preserved'])
            self.assertEqual(len([q for q in self.calls() if isinstance(q, dict) and q['method'] == 'thread/start']), 1)

    def test_malformed_rpc_fails_before_delivery(self):
        _, result = self.run_helper("codex-app", "send", CODEX, "--message", "hello", "--no-reply",
                                    mode="bad_rpc", ok=False)
        self.assertIn("invalid Codex App Server frame", result["error"])
        self.assertEqual(self.queue_calls(), [])

    def test_claude_inbox_exact_session_single_json_line(self):
        self.listen()
        text = '多行\n中文 $(touch NEVER) "quote"\n'
        _, result = self.run_helper("claude-app", "send", CLAUDE, "--message", text, "--no-reply")
        self.assertTrue(self.finished.wait(2))
        self.assertEqual(len(self.frames), 1)
        frame = self.frames[0]
        self.assertEqual(frame["session_id"], CLAUDE)
        self.assertEqual(frame["type"], "user")
        self.assertEqual(frame["priority"], "next")
        self.assertIn(text, frame["message"]["content"])
        self.assertNotIn("sender_mode", frame)
        self.assertEqual(result["status"], "submitted")
        self.assertEqual(result["delivery"], "unconfirmed")
        self.assertFalse((self.base / "NEVER").exists())

    def test_claude_list_excludes_cli_unknown_entry_and_stale_pid(self):
        row = self.listen(entrypoint="cli")
        path = self.registry / f"{os.getpid()}.json"
        for entry, stamp in [("cli", row["procStart"]), ("unknown", row["procStart"]),
                             ("claude-desktop", "stale process start")]:
            row.update(entrypoint=entry, procStart=stamp)
            path.write_text(json.dumps(row))
            _, result = self.run_helper("claude-app", "list")
            self.assertEqual(result["sessions"], [])
        self.assertEqual(self.frames, [])

    def test_claude_rejects_symlink_or_writable_endpoint(self):
        row = self.listen()
        path = self.registry / f"{os.getpid()}.json"
        path.chmod(0o666)
        _, result = self.run_helper("claude-app", "list")
        self.assertEqual(result["sessions"], [])
        path.chmod(0o600)
        link = self.base / "link.sock"
        link.symlink_to(row["messagingSocketPath"])
        row["messagingSocketPath"] = str(link)
        path.write_text(json.dumps(row))
        self.run_helper("claude-app", "send", CLAUDE, "--no-reply", "--message", "hello", ok=False)
        self.assertEqual(self.frames, [])

    def test_claude_verifies_socket_peer_pid_before_writing(self):
        row = self.listen()
        path = self.registry / f"{os.getpid()}.json"
        path.unlink()
        child = subprocess.Popen(["/bin/sleep", "10"])
        try:
            row.update(pid=child.pid, procStart=self.native_start(child.pid))
            (self.registry / f"{child.pid}.json").write_text(json.dumps(row))
            _, result = self.run_helper("claude-app", "send", CLAUDE, "--no-reply", "--message", "hello", ok=False)
            self.assertIn("peer PID mismatch", result["error"])
            self.assertTrue(self.finished.wait(2))
            self.assertEqual(self.frames, [])
        finally:
            child.terminate()
            child.wait()

    def test_cli_to_codex_request_carries_exact_cli_return_address(self):
        address = {"kind": "claude-cli", "target": "tc-project-main:2.1", "cwd": str(self.base),
                   "pane_id": "%3", "pane_pid": "1234", "native_session_id": CLAUDE}
        _, result = self.run_helper("codex-app", "send", CODEX, "--reply-to", json.dumps(address),
                                    "--request-id", REQUEST, "--message", "one question")
        request = result["envelope"]
        self.assertEqual(request["reply_to"], address)
        self.assertEqual(request["request_id"], REQUEST)

    def test_claude_app_to_codex_app_and_exact_inbox_callback(self):
        self.listen()
        _, address = self.run_helper("claude-app", "address", CLAUDE)
        _, receipt = self.run_helper("codex-app", "send", CODEX, "--reply-to", json.dumps(address),
                                     "--request-id", REQUEST, "--message", "test question")
        _, result = self.run_helper("reply", "--envelope", json.dumps(receipt["envelope"]),
                                    data="完整结果\n第二行")
        self.assertTrue(self.finished.wait(2))
        self.assertEqual(result["request_id"], REQUEST)
        content = self.frames[0]["message"]["content"]
        self.assertIn('"kind": "result"', content)
        self.assertIn(REQUEST, content)
        self.assertIn("完整结果\n第二行", content)

    def test_codex_app_to_claude_app_and_queue_callback(self):
        self.listen()
        _, address = self.run_helper("codex-app", "address", CODEX)
        _, receipt = self.run_helper("claude-app", "send", CLAUDE, "--reply-to", json.dumps(address),
                                     "--request-id", REQUEST, "--message", "question")
        self.assertTrue(self.finished.wait(2))
        _, result = self.run_helper("reply", "--envelope", json.dumps(receipt["envelope"]),
                                    "--message", "answer")
        self.assertEqual(result["status"], "queued")
        self.assertEqual(self.queue_calls()[0][2], CODEX)
        self.assertIn('"kind": "result"', self.queue_calls()[0][-1])

    def test_reply_refuses_result_or_changed_inbox_identity(self):
        self.listen()
        _, address = self.run_helper("claude-app", "address", CLAUDE)
        address["pid"] += 1
        request = bridge.envelope("request", {"kind": "codex-app", "target": CODEX}, address, "question", REQUEST)
        self.run_helper("reply", "--envelope", json.dumps(request), "--message", "answer", ok=False)
        request["kind"] = "result"
        self.run_helper("reply", "--envelope", json.dumps(request), "--message", "loop", ok=False)
        self.assertEqual(self.frames, [])
        self.assertEqual(self.queue_calls(), [])


if __name__ == "__main__":
    unittest.main()
