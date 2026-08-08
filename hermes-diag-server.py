#!/usr/bin/env python3
"""Hermes 端口诊断修复面板 — 后端"""

import http.server
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

# 双平台适配：Windows 侧运行（WSL 网络故障时面板仍可用）
IS_WIN = sys.platform.startswith("win")
WIN_USER_DIR = "C:\\Users\\77630"
WIN_CWD = WIN_USER_DIR if IS_WIN else "/mnt/c/Users/77630"

if IS_WIN:
    # Windows 控制台/文件输出默认 GBK，强制 UTF-8 避免 emoji/中文打印崩溃
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

PORT = int(os.environ.get("DIAG_PORT", "8920"))
BIND = os.environ.get("DIAG_BIND", "0.0.0.0")
HERE = Path(__file__).parent.resolve()
HTML_FILE = HERE / "hermes-diag.html"
FAVICON_FILE = HERE / "硬件进程网页图标.ico"

HERMES_PORTS = {
    8787: "WebUI",
    9119: "Dashboard",
    8900: "统一监控",
}


def run_cmd(cmd, timeout=8):
    """执行命令，返回 {ok, stdout, stderr}"""
    try:
        # cmd.exe 调用需指定 Windows 合法 cwd，并用 chcp 65001 避免编码问题
        if cmd.startswith("cmd.exe"):
            r = subprocess.run(cmd, shell=True, capture_output=True, timeout=timeout,
                               cwd=WIN_CWD)
            stdout = r.stdout.decode("utf-8", errors="replace").strip()
            stderr = r.stderr.decode("utf-8", errors="replace").strip()
        else:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            stdout = r.stdout.strip()
            stderr = r.stderr.strip()
        return {"ok": r.returncode == 0, "stdout": stdout, "stderr": stderr}
    except subprocess.TimeoutExpired:
        return {"ok": False, "stdout": "", "stderr": "timeout"}
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e)}


def get_wsl_ip():
    if IS_WIN:
        # Windows 侧通过 wsl.exe 获取（WSL 故障时返回 None，不影响面板本身）
        r = run_cmd("wsl.exe hostname -I", timeout=5)
        if r["ok"] and r["stdout"]:
            return r["stdout"].split()[0]
        try:
            txt = Path(WIN_USER_DIR + "\\wsl_ip.txt").read_text(encoding="utf-8").strip()
            return txt or None
        except Exception:
            return None
    r = run_cmd("hostname -I")
    if r["ok"]:
        return r["stdout"].split()[0] if r["stdout"] else None
    return None


def check_portproxy(port):
    r = run_cmd("cmd.exe /c \"chcp 65001 >nul && netsh interface portproxy show v4tov4\"")
    return bool(re.search(rf"0\.0\.0\.0\s+{port}\s+", r["stdout"]))


def check_firewall(port):
    r = run_cmd(f'cmd.exe /c \"chcp 65001 >nul && netsh advfirewall firewall show rule name=\\\"Hermes-Port-Forward-{port}\\\"\"')
    return "Enabled" in r["stdout"] or "已启用" in r["stdout"] or r["ok"]


def check_http(port):
    if IS_WIN:
        # Windows: -o NUL 丢弃body(避免 /dev/null 解析成文件路径导致 curl rc=23)，
        # 双引号是 cmd 的正确引号(单引号会被原样传给 curl，状态码带引号)
        r = run_cmd(f'curl.exe -s -o NUL -w "%{{http_code}}" --connect-timeout 3 http://127.0.0.1:{port}/health')
    else:
        r = run_cmd(f"curl -s -o /dev/null -w '%{{http_code}}' --connect-timeout 3 http://127.0.0.1:{port}/health")
    return r["ok"] and re.search(r"\b[23]\d\d\b", r["stdout"]) is not None


def get_all_status():
    wsl_ip = get_wsl_ip()
    ports_status = []
    all_ok = True
    for port, name in HERMES_PORTS.items():
        proxy = check_portproxy(port)
        fw = check_firewall(port)
        http = check_http(port) if proxy else False
        ok = http
        if not ok:
            all_ok = False
        ports_status.append({
            "port": port, "name": name, "ok": ok,
            "proxy": proxy, "firewall": fw, "http": http,
        })

    return {
        "wsl_ip": wsl_ip,
        "ports": ports_status,
        "all_ok": all_ok,
    }


def repair_port(port):
    wsl_ip = get_wsl_ip()
    if not wsl_ip:
        return {"ok": False, "error": "无法获取 WSL IP"}

    # 重建 portproxy
    run_cmd(f'cmd.exe /c "chcp 65001 >nul && netsh interface portproxy delete v4tov4 listenport={port} listenaddress=0.0.0.0"')
    r = run_cmd(f'cmd.exe /c "chcp 65001 >nul && netsh interface portproxy add v4tov4 listenport={port} listenaddress=0.0.0.0 connectport={port} connectaddress={wsl_ip}"')

    # 防火墙
    fw_name = f"Hermes-Port-Forward-{port}"
    run_cmd(f'cmd.exe /c "chcp 65001 >nul && netsh advfirewall firewall delete rule name=\\"{fw_name}\\""')
    run_cmd(f'cmd.exe /c "chcp 65001 >nul && netsh advfirewall firewall add rule name=\\"{fw_name}\\" dir=in action=allow protocol=TCP localport={port}"')

    time.sleep(0.5)
    ok = check_http(port)
    return {"ok": ok, "port": port, "proxy_ok": r["ok"]}


def repair_all_ports():
    results = []
    for port in HERMES_PORTS:
        results.append(repair_port(port))
    all_ok = all(r["ok"] for r in results)
    return {"ok": all_ok, "results": results}


def repair_wsl_network():
    steps = []
    for cmd, label in [
        ("chcp 65001 >nul && netsh winsock reset", "重置 WinSock"),
        ("chcp 65001 >nul && netsh int ip reset all", "重置 TCP/IP 协议栈"),
    ]:
        r = run_cmd(f'cmd.exe /c "{cmd}"', timeout=15)
        steps.append({"label": label, "ok": r["ok"]})

    run_cmd("wsl.exe --shutdown", timeout=10)
    steps.append({"label": "关闭 WSL", "ok": True})

    time.sleep(5)
    # 唤醒 WSL
    run_cmd("wsl -e echo ok", timeout=10)
    return {"ok": True, "steps": steps, "note": "建议重启 Windows 使网络重置完全生效"}


def start_hermes():
    """运行 WSL_Start_Hermes"""
    if IS_WIN:
        r = run_cmd('wsl.exe bash -lc "~/start_hermes.sh"', timeout=30)
    else:
        r = run_cmd("bash ~/start_hermes.sh", timeout=30)
    return {"ok": r["ok"], "stdout": r["stdout"][-500:], "stderr": r["stderr"][-200:]}


def run_port_forward():
    """运行 Hermes_Port_Forward（Windows PowerShell 脚本）"""
    r = run_cmd(
        'cmd.exe /c "powershell -ExecutionPolicy Bypass -File C:\\Users\\77630\\port_forward_hermes.ps1"',
        timeout=20,
    )
    return {"ok": r["ok"], "stdout": r["stdout"][-500:]}


def exec_terminal(term, cmd):
    """在指定终端执行命令。term: powershell/cmd/wsl"""
    if term == "powershell":
        # 用 PowerShell 直接调用，避免 cmd 嵌套引号问题
        r = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", cmd],
            capture_output=True, timeout=30, cwd=WIN_CWD
        )
        stdout = r.stdout.decode("utf-8", errors="replace").strip()
        stderr = r.stderr.decode("utf-8", errors="replace").strip()
        ok = r.returncode == 0
    elif term == "cmd":
        r = run_cmd(f'cmd.exe /c "chcp 65001 >nul && {cmd}"', timeout=30)
        stdout = r["stdout"]
        stderr = r["stderr"]
        ok = r["ok"]
    elif term == "wsl":
        if IS_WIN:
            r = run_cmd(f'wsl.exe bash -c "{cmd}"', timeout=30)
        else:
            r = run_cmd(f'bash -c "{cmd}"', timeout=30)
        stdout = r["stdout"]
        stderr = r["stderr"]
        ok = r["ok"]
    else:
        return {"ok": False, "stdout": "", "stderr": f"未知终端: {term}"}

    return {
        "ok": ok,
        "stdout": stdout[-8000:],
        "stderr": stderr[-2000:],
    }


class DiagHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, content):
        body = content.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path in ("/", "/index.html"):
            try:
                self._send_html(HTML_FILE.read_text(encoding="utf-8"))
            except FileNotFoundError:
                self._send_json({"error": "HTML not found"}, 404)
            return

        if path == "/favicon.ico" and FAVICON_FILE.exists():
            self.send_response(200)
            self.send_header("Content-Type", "image/x-icon")
            self.send_header("Content-Length", str(FAVICON_FILE.stat().st_size))
            self.end_headers()
            self.wfile.write(FAVICON_FILE.read_bytes())
            return

        routes = {
            "/api/status": get_all_status,
            "/api/repair-all": repair_all_ports,
            "/api/repair-wsl": repair_wsl_network,
            "/api/start-hermes": start_hermes,
            "/api/port-forward": run_port_forward,
        }

        if path in routes:
            self._send_json(routes[path]())
            return

        if path == "/health":
            self._send_json({"status": "ok"})
            return

        self._send_json({"error": "Not Found"}, 404)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/terminal":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            term = body.get("term", "wsl")
            cmd = body.get("cmd", "")
            if not cmd.strip():
                self._send_json({"ok": False, "stdout": "", "stderr": "命令不能为空"}, 400)
                return
            self._send_json(exec_terminal(term, cmd))
            return
        self._send_json({"error": "Not Found"}, 404)


def main():
    if IS_WIN:
        # 避免 UNC 当前目录问题
        try:
            os.chdir(WIN_CWD)
        except Exception:
            pass
    print(f"🔧 Hermes 端口诊断面板")
    print(f"   端口: {PORT}")
    print(f"   访问: http://localhost:{PORT}")
    print()

    server = http.server.HTTPServer((BIND, PORT), DiagHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n⏹ 已停止")
        server.shutdown()


if __name__ == "__main__":
    main()
