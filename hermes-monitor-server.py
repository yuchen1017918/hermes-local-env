#!/usr/bin/env python3
"""Hermes 统一监控面板后端 — 进程监控 + 日志查看器"""

import http.server
import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import psutil

# ========== 配置 ==========
PORT = int(os.environ.get("HERMES_MONITOR_PORT", "8900"))
BIND = os.environ.get("HERMES_MONITOR_BIND", "0.0.0.0")

HERE = Path(__file__).parent.resolve()
HTML_FILE = HERE / "hermes-monitor.html"
FAVICON_FILE = HERE / "图标.ico"

# 日志文件路径
LOG_FILES = {
    "gateway": Path.home() / ".hermes" / "logs" / "gateway.log",
    "web": Path.home() / ".hermes" / "webui" / "bootstrap-8787.log",
}

# Hermes 进程匹配模式
HERMES_PATTERNS = [
    "hermes", "bootstrap.py", "hermes-webui",
    "hermes-log-server", "hermes-monitor",
]


# ========== 系统/进程监控 ==========

def get_system_stats():
    cpu_pct = psutil.cpu_percent(interval=0.1)
    cpu_count = psutil.cpu_count()
    cpu_freq = psutil.cpu_freq()
    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()
    disk = psutil.disk_usage("/")
    disk_io = psutil.disk_io_counters()
    net = psutil.net_io_counters()

    temps = {}
    try:
        t = psutil.sensors_temperatures()
        if t:
            for name, entries in list(t.items())[:2]:
                if entries:
                    temps[name] = round(entries[0].current, 1)
    except Exception:
        pass

    return {
        "cpu": {
            "percent": round(cpu_pct, 1),
            "count": cpu_count,
            "freq_current": round(cpu_freq.current, 1) if cpu_freq else 0,
        },
        "memory": {
            "total_gb": round(mem.total / 1024 ** 3, 1),
            "used_gb": round(mem.used / 1024 ** 3, 1),
            "percent": round(mem.percent, 1),
            "available_gb": round(mem.available / 1024 ** 3, 1),
            "swap_percent": round(swap.percent, 1),
            "swap_used_gb": round(swap.used / 1024 ** 3, 1),
        },
        "disk": {
            "total_gb": round(disk.total / 1024 ** 3, 1),
            "used_gb": round(disk.used / 1024 ** 3, 1),
            "percent": round(disk.percent, 1),
            "read_mb": round(disk_io.read_bytes / 1024 ** 2, 1) if disk_io else 0,
            "write_mb": round(disk_io.write_bytes / 1024 ** 2, 1) if disk_io else 0,
        },
        "network": {
            "sent_mb": round(net.bytes_sent / 1024 ** 2, 1) if net else 0,
            "recv_mb": round(net.bytes_recv / 1024 ** 2, 1) if net else 0,
        },
        "temps": temps,
        "boot_time": psutil.boot_time(),
        "uptime_seconds": round(time.time() - psutil.boot_time(), 0),
    }


def find_hermes_processes():
    procs = []
    for p in psutil.process_iter(
        ["pid", "name", "cmdline", "cpu_percent", "memory_percent",
         "memory_info", "create_time", "status"]
    ):
        try:
            info = p.info
            cmdline = " ".join(info.get("cmdline") or [])
            name = (info.get("name") or "").lower()
            combined = (name + " " + cmdline).lower()

            is_hermes = any(pat.lower() in combined for pat in HERMES_PATTERNS)
            if not is_hermes:
                continue

            mem = info.get("memory_info")
            procs.append({
                "pid": info["pid"],
                "name": info["name"],
                "cmdline": cmdline[:200],
                "cpu_percent": round(info.get("cpu_percent") or 0, 1),
                "mem_percent": round(info.get("memory_percent") or 0, 1),
                "mem_rss_mb": round(mem.rss / 1024 / 1024, 1) if mem else 0,
                "mem_vms_mb": round(mem.vms / 1024 / 1024, 1) if mem else 0,
                "status": info.get("status", "?"),
                "create_time": info.get("create_time", 0),
                "running_seconds": round(
                    time.time() - (info.get("create_time") or time.time()), 0
                ),
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return sorted(procs, key=lambda x: x["cpu_percent"], reverse=True)


# ========== 日志读取 ==========

def read_tail(filepath: Path, cursor: int, max_lines: int) -> dict:
    if not filepath.exists():
        return {"lines": [], "next_cursor": 0, "error": f"文件不存在: {filepath}"}

    try:
        stat = filepath.stat()
        file_size = stat.st_size

        if cursor > file_size:
            cursor = 0

        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            lines = []
            new_cursor = file_size

            if cursor == 0:
                chunk_size = 4096
                blocks = []
                remaining_lines = max_lines + 1
                pos = file_size

                while pos > 0 and remaining_lines > 0:
                    read_size = min(chunk_size, pos)
                    pos -= read_size
                    f.seek(pos)
                    chunk = f.read(read_size)
                    blocks.append(chunk)
                    remaining_lines -= chunk.count("\n")

                tail_text = "".join(reversed(blocks))
                all_tail_lines = tail_text.split("\n")
                lines = [l for l in all_tail_lines if l][-max_lines:]
            else:
                f.seek(cursor)
                if cursor != 0:
                    f.readline()
                for line in f:
                    line = line.rstrip("\n\r")
                    if line:
                        lines.append(line)
                new_cursor = f.tell()

        return {
            "lines": lines,
            "next_cursor": new_cursor,
            "file_size": file_size,
            "error": None,
        }
    except Exception as e:
        return {"lines": [], "next_cursor": cursor, "error": str(e)}


# ========== HTTP Handler ==========

class MonitorHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, content, status=200):
        body = content.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, msg, status=500):
        self._send_json({"error": msg}, status)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        # 主页
        if path == "/" or path == "/index.html":
            if HTML_FILE.exists():
                self._send_html(HTML_FILE.read_text(encoding="utf-8"))
            else:
                self._send_html(
                    f"<h1>404</h1><p>{HTML_FILE} 不存在</p>", 404
                )
            return

        # Favicon
        if path == "/favicon.ico" and FAVICON_FILE.exists():
            self.send_response(200)
            self.send_header("Content-Type", "image/x-icon")
            self.send_header("Content-Length", str(FAVICON_FILE.stat().st_size))
            self.end_headers()
            self.wfile.write(FAVICON_FILE.read_bytes())
            return

        # 健康检查
        if path == "/health":
            self._send_json({"status": "ok"})

        # 系统 + 进程状态
        elif path == "/api/all" or path == "/api/status":
            self._send_json({
                "system": get_system_stats(),
                "processes": find_hermes_processes(),
            })

        # 日志读取
        elif path == "/api/tail":
            file_key = params.get("file", [None])[0]
            if file_key not in LOG_FILES:
                self._send_error(f"无效文件: {file_key}, 可选: {list(LOG_FILES.keys())}", 400)
                return
            try:
                cursor = int(params.get("cursor", [0])[0])
            except (ValueError, TypeError):
                cursor = 0
            try:
                max_lines = int(params.get("max_lines", [500])[0])
            except (ValueError, TypeError):
                max_lines = 500

            result = read_tail(LOG_FILES[file_key], cursor, max_lines)
            self._send_json(result)

        # 日志文件信息
        elif path == "/api/log-status":
            info = {}
            for key, fp in LOG_FILES.items():
                if fp.exists():
                    info[key] = {
                        "exists": True,
                        "size": fp.stat().st_size,
                        "size_mb": round(fp.stat().st_size / 1024 / 1024, 2),
                    }
                else:
                    info[key] = {"exists": False, "size": 0, "size_mb": 0}
            self._send_json(info)

        # Kill 进程
        elif path == "/api/kill":
            try:
                pid = int(params.get("pid", [None])[0])
            except (TypeError, ValueError):
                self._send_error("缺少 pid 参数", 400)
                return
            try:
                os.kill(pid, signal.SIGKILL)
                self._send_json({"ok": True, "pid": pid})
            except Exception as e:
                self._send_json({"ok": False, "error": str(e)})

        # 运行命令行
        elif path == "/api/run":
            cmd = params.get("cmd", [None])[0]
            if not cmd:
                self._send_error("缺少 cmd 参数", 400)
                return
            try:
                r = subprocess.run(
                    cmd, shell=True, capture_output=True,
                    text=True, timeout=30
                )
                self._send_json({
                    "ok": r.returncode == 0,
                    "stdout": r.stdout[:2000],
                    "stderr": r.stderr[:500],
                })
            except Exception as e:
                self._send_json({"ok": False, "error": str(e)})

        else:
            self._send_error(f"Unknown: {path}", 404)


if __name__ == "__main__":
    print(f"🚀 Hermes 统一监控面板启动: http://{BIND}:{PORT}")
    print(f"   API: /api/status | /api/tail | /api/kill | /api/run")
    print(f"   日志: gateway={LOG_FILES['gateway'].exists()} | web={LOG_FILES['web'].exists()}")
    server = http.server.HTTPServer((BIND, PORT), MonitorHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n关闭服务...")
        server.shutdown()
