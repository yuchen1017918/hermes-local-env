#!/usr/bin/env python3
"""Hermes 端口诊断修复面板 — 后端"""

import http.server
import json
import os
import re
import subprocess
import time
import urllib.parse
from pathlib import Path

PORT = int(os.environ.get("DIAG_PORT", "8920"))
BIND = os.environ.get("DIAG_BIND", "0.0.0.0")
HERE = Path(__file__).parent.resolve()
HTML_FILE = HERE / "hermes-diag.html"
FAVICON_FILE = HERE / "硬件进程网页图标.ico"

HERMES_PORTS = {
    8787: "WebUI",
    9119: "Dashboard",
    8900: "统一监控",
    8920: "端口诊断",
}


def run_cmd(cmd, timeout=8):
    """执行命令，返回 {ok, stdout, stderr}"""
    try:
        # cmd.exe 从 WSL 调用需指定 Windows 合法 cwd，并用 chcp 65001 避免编码问题
        if cmd.startswith("cmd.exe"):
            r = subprocess.run(cmd, shell=True, capture_output=True, timeout=timeout,
                               cwd="/mnt/c/Users/77630")
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
    r = run_cmd("bash ~/start_hermes.sh", timeout=30)
    return {"ok": r["ok"], "stdout": r["stdout"][-500:], "stderr": r["stderr"][-200:]}


def run_port_forward():
    """运行 Hermes_Port_Forward（Windows PowerShell 脚本）"""
    r = run_cmd(
        'cmd.exe /c "powershell -ExecutionPolicy Bypass -File C:\\Users\\77630\\port_forward_hermes.ps1"',
        timeout=20,
    )
    return {"ok": r["ok"], "stdout": r["stdout"][-500:]}


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


def main():
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
