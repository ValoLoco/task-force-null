#!/usr/bin/env python3
"""Localhost real-time web TOC for Task Force Null (stdlib only)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import threading
import time
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import toc_lib  # noqa: E402

ALLOWED_GET = {"/", "/api/state", "/events"}

DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Task Force Null TOC</title>
<!-- TFN_TOC_WEB -->
<style>
:root {
  --bg: #f4f6f8;
  --panel: #ffffff;
  --text: #1a1f26;
  --muted: #5c6773;
  --accent: #0b6e4f;
  --border: #d8dee4;
  --pill-ok: #0b6e4f;
  --pill-warn: #b58105;
  --todo: #5c6773;
  --doing: #1565c0;
  --done: #2e7d32;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #0d1117;
    --panel: #161b22;
    --text: #e6edf3;
    --muted: #8b949e;
    --accent: #3fb950;
    --border: #30363d;
  }
}
[data-theme="dark"] {
  --bg: #0d1117;
  --panel: #161b22;
  --text: #e6edf3;
  --muted: #8b949e;
  --accent: #3fb950;
  --border: #30363d;
}
[data-theme="light"] {
  --bg: #f4f6f8;
  --panel: #ffffff;
  --text: #1a1f26;
  --muted: #5c6773;
  --accent: #0b6e4f;
  --border: #d8dee4;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.45;
  font-size: 14px;
}
header {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--panel);
  border-bottom: 1px solid var(--border);
  padding: 12px 20px;
}
.hdr-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
  justify-content: space-between;
}
h1 {
  margin: 0;
  font-size: 1.1rem;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
#tfn-toc-dashboard { display: contents; }
.meta { color: var(--muted); font-size: 0.85rem; }
.strip {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 8px;
}
.badge {
  padding: 2px 8px;
  border-radius: 4px;
  border: 1px solid var(--border);
  font-size: 0.8rem;
  background: var(--bg);
}
.pill {
  padding: 2px 10px;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 600;
}
.pill-live { background: var(--pill-ok); color: #fff; }
.pill-recon { background: var(--pill-warn); color: #fff; }
main {
  padding: 16px 20px 40px;
  max-width: 1400px;
  margin: 0 auto;
  display: grid;
  gap: 16px;
}
@media (min-width: 960px) {
  main { grid-template-columns: 1fr 1fr; }
  .span2 { grid-column: 1 / -1; }
}
.panel {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 14px 16px;
}
.panel h2 {
  margin: 0 0 10px;
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--muted);
}
.mission-card {
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 10px 12px;
  margin-bottom: 10px;
}
.mission-card h3 { margin: 0 0 6px; font-size: 0.95rem; }
.progress {
  height: 6px;
  background: var(--border);
  border-radius: 3px;
  overflow: hidden;
  margin: 6px 0;
}
.progress > span {
  display: block;
  height: 100%;
  background: var(--accent);
}
.kanban {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
  margin-top: 8px;
}
.col h4 {
  margin: 0 0 4px;
  font-size: 0.7rem;
  color: var(--muted);
  text-transform: uppercase;
}
.task-chip {
  font-size: 0.75rem;
  padding: 4px 6px;
  border-radius: 4px;
  border: 1px solid var(--border);
  margin-bottom: 4px;
  background: var(--bg);
}
.roster {
  display: grid;
  gap: 8px;
}
.op {
  border-left: 3px solid var(--accent);
  padding-left: 8px;
}
.op-id { font-weight: 600; font-size: 0.85rem; }
.log-box {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.75rem;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  max-height: 200px;
  overflow: auto;
  padding: 8px;
  white-space: pre-wrap;
}
.tabs { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px; }
.tab {
  padding: 4px 10px;
  border: 1px solid var(--border);
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.75rem;
  background: var(--bg);
}
.tab.active { border-color: var(--accent); color: var(--accent); }
button.theme {
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--text);
  padding: 4px 10px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.8rem;
}
.aar { border-bottom: 1px solid var(--border); padding: 8px 0; }
.aar:last-child { border-bottom: none; }
.muted { color: var(--muted); }
.status-done { border-left-color: var(--done); }
.status-todo { border-left-color: var(--todo); }
.status-doing { border-left-color: var(--doing); }
</style>
</head>
<body>
<header>
  <div id="tfn-toc-dashboard" class="hdr-row">
    <h1>Task Force Null TOC</h1>
    <div>
      <span class="meta" id="utc-clock">UTC --</span>
      <span class="pill pill-recon" id="sse-pill">connecting</span>
      <button type="button" class="theme" id="theme-btn" aria-label="Toggle theme">Theme</button>
    </div>
  </div>
  <div class="strip" id="status-strip"></div>
</header>
<main>
  <section class="panel span2" id="missions-panel"><h2>Active missions</h2><div id="missions"></div></section>
  <section class="panel" id="roster-panel"><h2>Operator roster</h2><div class="roster" id="roster"></div></section>
  <section class="panel" id="logs-panel"><h2>Operator logs</h2>
    <div class="tabs" id="log-tabs"></div>
    <div class="log-box" id="log-view">No operator log files yet. Logs appear when missions write under missions/*/logs/*.log</div>
  </section>
  <section class="panel" id="aars-panel"><h2>Recent AARs</h2><div id="aars"></div></section>
  <section class="panel" id="routing-panel"><h2>Model routing</h2><div id="routing"></div></section>
  <section class="panel" id="armory-panel"><h2>Armory</h2><div id="armory"></div></section>
</main>
<script>
(function () {
  const pill = document.getElementById('sse-pill');
  const themeBtn = document.getElementById('theme-btn');
  const root = document.documentElement;
  const stored = localStorage.getItem('tfn-toc-theme');
  if (stored === 'light' || stored === 'dark') root.setAttribute('data-theme', stored);

  themeBtn.addEventListener('click', function () {
    const cur = root.getAttribute('data-theme');
    let next = 'dark';
    if (cur === 'dark') next = 'light';
    else if (cur === 'light') next = '';
    if (next) {
      root.setAttribute('data-theme', next);
      localStorage.setItem('tfn-toc-theme', next);
    } else {
      root.removeAttribute('data-theme');
      localStorage.removeItem('tfn-toc-theme');
    }
  });

  function tickClock() {
    const el = document.getElementById('utc-clock');
    el.textContent = 'UTC ' + new Date().toISOString().replace('.000', '').replace(/\.\d{3}/, '');
  }
  setInterval(tickClock, 1000);
  tickClock();

  const logBuffers = {};
  let activeLog = '';

  function statusBucket(st) {
    const s = (st || '').toLowerCase();
    if (s === 'done' || s === 'complete' || s === 'closed') return 'done';
    if (s === 'doing' || s === 'in progress' || s === 'active') return 'doing';
    return 'todo';
  }

  function renderState(data) {
    const strip = data.status_strip || {};
    const mat = strip.maturity || {};
    const del = strip.delegation || {};
    document.getElementById('status-strip').innerHTML = [
      '<span class="badge">blockers ' + (del.blockers ? 'ON' : 'OFF') + '</span>',
      '<span class="badge">external ' + (del.external ? 'ON' : 'OFF') + '</span>',
      '<span class="badge">autonomous ' + (strip.autonomous ? 'ON' : 'OFF') + '</span>',
      '<span class="badge">AARs ' + mat.aar_count + '/' + mat.min_aars + '</span>',
      '<span class="badge">missions ' + mat.completed_missions + '/' + mat.min_missions + '</span>',
      '<span class="badge">' + (mat.pushback || '') + '</span>'
    ].join('');

    const missionsEl = document.getElementById('missions');
    missionsEl.innerHTML = '';
    (data.missions || []).forEach(function (m) {
      const card = document.createElement('div');
      card.className = 'mission-card';
      const buckets = { todo: [], doing: [], done: [] };
      (m.tasks || []).forEach(function (t) {
        buckets[statusBucket(t.status)].push(t);
      });
      card.innerHTML = '<h3>' + m.slug + ' <span class="muted">' +
        (m.active ? 'ACTIVE' : 'INACTIVE') + ' ' + m.pct + '% (' + m.done + '/' + m.total + ')</span></h3>' +
        '<p class="muted">' + (m.objective || '') + '</p>' +
        '<div class="progress"><span style="width:' + m.pct + '%"></span></div>';
      const kb = document.createElement('div');
      kb.className = 'kanban';
      ['todo', 'doing', 'done'].forEach(function (col) {
        const c = document.createElement('div');
        c.className = 'col';
        c.innerHTML = '<h4>' + col + '</h4>';
        buckets[col].forEach(function (t) {
          const chip = document.createElement('div');
          chip.className = 'task-chip status-' + col;
          chip.textContent = t.id + ' ' + t.owner + ': ' + t.name;
          c.appendChild(chip);
        });
        kb.appendChild(c);
      });
      card.appendChild(kb);
      missionsEl.appendChild(card);
    });

    const rosterEl = document.getElementById('roster');
    rosterEl.innerHTML = '';
    (data.operators || []).forEach(function (op) {
      const d = document.createElement('div');
      d.className = 'op';
      let tasks = (op.tasks || []).map(function (t) {
        return t.mission + '/' + t.id + ' [' + t.status + ']';
      }).join(', ');
      if (!tasks) tasks = '<span class="muted">(no owned tasks)</span>';
      d.innerHTML = '<div class="op-id">' + op.id + '</div><div class="muted">' + op.title + '</div><div>' + tasks + '</div>';
      rosterEl.appendChild(d);
    });

    const aarsEl = document.getElementById('aars');
    aarsEl.innerHTML = '';
    const aars = data.aars || [];
    if (!aars.length) {
      aarsEl.innerHTML = '<p class="muted">(none recorded)</p>';
    } else {
      aars.slice().reverse().slice(0, 12).forEach(function (a) {
        const div = document.createElement('div');
        div.className = 'aar';
        div.innerHTML = '<strong>' + a.head + '</strong>' +
          (a.outcome ? '<div>outcome: ' + a.outcome + '</div>' : '') +
          (a.friction ? '<div>friction: ' + a.friction + '</div>' : '') +
          (a.fix ? '<div>fix: ' + a.fix + '</div>' : '');
        aarsEl.appendChild(div);
      });
    }

    const routing = data.routing || {};
    let rhtml = '<div>harness: ' + (routing.harness || '') + '</div>';
    if (routing.inventory && routing.inventory.length) {
      rhtml += '<div>inventory: ' + routing.inventory.map(function (i) {
        return i.model_id + ' (' + i.provider + ')';
      }).join('; ') + '</div>';
    } else rhtml += '<div class="muted">inventory: (none)</div>';
    if (routing.learned_overrides && routing.learned_overrides.length) {
      rhtml += '<div>overrides: ' + routing.learned_overrides.map(function (o) {
        return o.task_pattern + ' -> ' + o.model_id;
      }).join('; ') + '</div>';
    }
    if (routing.bindings && routing.bindings.length) {
      rhtml += '<div>bindings: ' + routing.bindings.map(function (b) {
        return b.mission + ' ' + b.bind;
      }).join('; ') + '</div>';
    } else rhtml += '<div class="muted">bindings: (none)</div>';
    document.getElementById('routing').innerHTML = rhtml;

    const arm = data.armory || {};
    document.getElementById('armory').innerHTML =
      '<div>armory/ecc: ' + (arm.present ? 'present' : 'missing') + '</div>' +
      '<div>PINNED_SHA: ' + (arm.pinned_sha || '') + '</div>';

    const tabs = document.getElementById('log-tabs');
    const logs = data.operator_logs || [];
    if (!logs.length) {
      tabs.innerHTML = '';
      if (!activeLog) {
        document.getElementById('log-view').textContent =
          'No operator log files yet. Logs appear when missions write under missions/*/logs/*.log';
      }
    } else {
      tabs.innerHTML = '';
      logs.forEach(function (lg) {
        const key = lg.path;
        if (!logBuffers[key]) logBuffers[key] = '';
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'tab' + (activeLog === key ? ' active' : '');
        btn.textContent = lg.mission + '/' + lg.name;
        btn.addEventListener('click', function () {
          activeLog = key;
          document.querySelectorAll('.tab').forEach(function (t) { t.classList.remove('active'); });
          btn.classList.add('active');
          document.getElementById('log-view').textContent = logBuffers[key] || '(waiting for log lines)';
        });
        tabs.appendChild(btn);
      });
      if (!activeLog && logs[0]) activeLog = logs[0].path;
    }
  }

  function appendLog(payload) {
    const key = payload.path || '';
    const line = payload.line || '';
    if (!key) return;
    if (!logBuffers[key]) logBuffers[key] = '';
    logBuffers[key] += line + '\n';
    if (key === activeLog) {
      const v = document.getElementById('log-view');
      v.textContent = logBuffers[key];
      v.scrollTop = v.scrollHeight;
    }
  }

  function connect() {
    const es = new EventSource('/events');
    es.addEventListener('state', function (ev) {
      try {
        renderState(JSON.parse(ev.data));
        pill.textContent = 'live';
        pill.className = 'pill pill-live';
      } catch (e) { /* ignore */ }
    });
    es.addEventListener('log', function (ev) {
      try { appendLog(JSON.parse(ev.data)); } catch (e) { /* ignore */ }
    });
    es.onerror = function () {
      pill.textContent = 'reconnecting';
      pill.className = 'pill pill-recon';
    };
    es.onopen = function () {
      pill.textContent = 'live';
      pill.className = 'pill pill-live';
    };
  }
  connect();
})();
</script>
</body>
</html>
"""


class TOCWebContext:
    def __init__(self, repo_root: Path, poll_interval: float) -> None:
        self.repo_root = repo_root.resolve()
        self.poll_interval = poll_interval
        self.lock = threading.Lock()
        self._log_offsets: dict[str, int] = {}

    def state_snapshot(self) -> dict[str, Any]:
        with self.lock:
            return toc_lib.collect_state(self.repo_root)

    def fingerprint(self) -> str:
        parts: list[str] = []
        for path in toc_lib.watch_paths(self.repo_root):
            safe = toc_lib.safe_under_repo(self.repo_root, path)
            if not safe or not safe.is_file():
                continue
            try:
                data = safe.read_bytes()
                st = safe.stat()
                parts.append("%s:%s:%s:%s" % (safe, st.st_mtime_ns, st.st_size, hashlib.sha256(data).hexdigest()))
            except OSError:
                continue
        return hashlib.sha256("|".join(sorted(parts)).encode()).hexdigest()

    def poll_log_lines(self) -> list[dict[str, str]]:
        events: list[dict[str, str]] = []
        for meta in toc_lib.discover_operator_logs(self.repo_root):
            rel = meta["path"]
            full = self.repo_root / rel
            safe = toc_lib.safe_under_repo(self.repo_root, full)
            if not safe or not safe.is_file():
                continue
            try:
                size = safe.stat().st_size
                offset = self._log_offsets.get(rel, 0)
                if size < offset:
                    offset = 0
                if size == offset:
                    self._log_offsets[rel] = offset
                    continue
                with safe.open("rb") as fh:
                    fh.seek(offset)
                    chunk = fh.read()
                self._log_offsets[rel] = offset + len(chunk)
                text = chunk.decode("utf-8", errors="replace")
                for line in text.splitlines():
                    events.append({"path": rel, "line": line, "mission": meta["mission"], "name": meta["name"]})
            except OSError:
                continue
        return events


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_meta(repo: Path) -> dict[str, Any] | None:
    meta_path = repo / ".toc-web.json"
    if not meta_path.is_file():
        return None
    try:
        return json.loads(meta_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def write_meta(repo: Path, meta: dict[str, Any]) -> None:
    path = repo / ".toc-web.json"
    path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")


def remove_meta(repo: Path) -> None:
    path = repo / ".toc-web.json"
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def should_open_browser(no_open: bool) -> bool:
    if no_open:
        return False
    if os.environ.get("SSH_CONNECTION") or os.environ.get("SSH_TTY"):
        return False
    if sys.platform.startswith("linux"):
        if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
            return False
    return True


def open_browser(url: str) -> None:
    try:
        if webbrowser.open(url):
            return
    except Exception:
        pass
    for cmd in (
        ["xdg-open", url],
        ["open", url],
        ["termux-open-url", url],
    ):
        try:
            if subprocess.run(
                ["which", cmd[0]],
                capture_output=True,
                check=False,
            ).returncode == 0:
                subprocess.run(cmd, check=False, capture_output=True)
                return
        except Exception:
            continue


def make_handler(ctx: TOCWebContext):
    class Handler(BaseHTTPRequestHandler):
        server_version = "TFN-TOC/1.0"

        def log_message(self, fmt: str, *args: Any) -> None:
            return

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            path = parsed.path
            if path not in ALLOWED_GET:
                self.send_error(404)
                return
            if path == "/":
                body = DASHBOARD_HTML.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if path == "/api/state":
                payload = json.dumps(ctx.state_snapshot(), separators=(",", ":")).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            if path == "/events":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                self._sse_stream()
                return

        def _sse_write(self, chunk: bytes) -> bool:
            try:
                self.wfile.write(chunk)
                self.wfile.flush()
                return True
            except (BrokenPipeError, ConnectionResetError, OSError):
                return False

        def _sse_stream(self) -> None:
            try:
                state = ctx.state_snapshot()
                data = json.dumps(state, separators=(",", ":"))
                if not self._sse_write(("event: state\ndata: %s\n\n" % data).encode("utf-8")):
                    return
                last_fp = ctx.fingerprint()
                last_heartbeat = time.monotonic()
                while True:
                    time.sleep(ctx.poll_interval)
                    fp = ctx.fingerprint()
                    if fp != last_fp:
                        last_fp = fp
                        state = ctx.state_snapshot()
                        data = json.dumps(state, separators=(",", ":"))
                        if not self._sse_write(
                            ("event: state\ndata: %s\n\n" % data).encode("utf-8")
                        ):
                            return
                    for ev in ctx.poll_log_lines():
                        line = json.dumps(ev, separators=(",", ":"))
                        if not self._sse_write(
                            ("event: log\ndata: %s\n\n" % line).encode("utf-8")
                        ):
                            return
                    now = time.monotonic()
                    if now - last_heartbeat >= 15.0:
                        last_heartbeat = now
                        if not self._sse_write(b": heartbeat\n\n"):
                            return
            except Exception:
                return

    return Handler


class ReuseHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Task Force Null web TOC")
    parser.add_argument("--repo-root", default=str(SCRIPT_DIR.parent))
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--poll-interval", type=float, default=1.0)
    return parser.parse_args()


def resolve_port(args: argparse.Namespace) -> int:
    env = os.environ.get("TFN_TOC_PORT", "").strip()
    if args.port is not None:
        return int(args.port)
    if env:
        return int(env)
    return 0


def main() -> int:
    args = parse_args()
    repo = Path(args.repo_root).resolve()
    if not repo.is_dir():
        print("toc-web: invalid repo root: %s" % repo, file=sys.stderr)
        return 2

    existing = read_meta(repo)
    if existing:
        ex_root = str(existing.get("repo_root", ""))
        ex_pid = int(existing.get("pid", 0) or 0)
        ex_url = existing.get("url", "")
        if ex_root == str(repo) and pid_alive(ex_pid) and ex_url:
            print(ex_url, flush=True)
            return 0

    port_want = resolve_port(args)
    ctx = TOCWebContext(repo, max(0.2, float(args.poll_interval)))
    handler = make_handler(ctx)
    httpd = ReuseHTTPServer(("127.0.0.1", port_want), handler)
    host, port = httpd.server_address
    url = "http://127.0.0.1:%s" % port
    started = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    meta = {
        "pid": os.getpid(),
        "port": port,
        "url": url,
        "started_at": started,
        "repo_root": str(repo),
    }
    write_meta(repo, meta)

    shutting_down = threading.Event()

    def shutdown(signum: int, _frame: Any) -> None:
        if shutting_down.is_set():
            return
        shutting_down.set()
        remove_meta(repo)
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    print(url, flush=True)
    if should_open_browser(args.no_open):
        threading.Thread(target=lambda: open_browser(url), daemon=True).start()

    try:
        httpd.serve_forever()
    finally:
        remove_meta(repo)
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())