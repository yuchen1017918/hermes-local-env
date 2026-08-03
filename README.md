# Hermes 监控面板

Hermes Agent 统一监控面板：系统进程 + 实时日志 + 端口诊断。

![](https://img.shields.io/badge/Python-3.11-blue) ![](https://img.shields.io/badge/端口-8900%2C8920-green)

## 面板

| 面板 | 端口 | 路径 | 说明 |
|------|------|------|------|
| 统一监控 | 8900 | `monitor/` | 左=进程仪表盘，右=Gateway+Web 日志，分屏可拖拽 |
| 端口诊断 | 8920 | `port-diag/` | 检测/修复 WSL 端口转发 + 防火墙，一键启动 Hermes |

## 统一监控 (8900)

### 布局

```
┌──────────────────────┬──┬────────────────────────────┐
│    左侧 50%           │  │      右侧 50%              │
│                      │  │                            │
│  CPU  内存  磁盘 SWAP │  │  [Gateway 日志] [Web 日志] │
│  ████  ████  ██  ██  │  │                            │
│                      │  │  2025-01-01 12:00:00 ...   │
│  ┌─CPU趋势──┐ ┌内存──┐│  │  2025-01-01 12:00:01 ...   │
│  │  📈     ││ 📈   ││  │  2025-01-01 12:00:02 ...   │
│  └─────────┘ └──────┘│  │                            │
│                      │  │                            │
│  PID  名称  CPU RSS   │  │                            │
│  123  hermes 5% 200M │  │                            │
│  456  python  2% 80M │  │                            │
│  789  node    1% 50M │  │                            │
└──────────────────────┴──┴────────────────────────────┘
        ◄── 分割线可拖动 (20%~65%) ──►
```

### 功能

- **仪表盘**：CPU/内存/磁盘/SWAP 实时百分比 + 进度条
- **趋势图**：CPU 和内存 60 点折线趋势（Chart.js）
- **进程表**：Hermes 相关进程，支持排序、Kill、重新启动
- **日志面板**：Gateway 日志 + Web UI 日志，Tab 切换
- **日志搜索**：关键词实时过滤
- **行数选择**：200/500/1000/2000 行
- **自动刷新**：进程 3s、日志 2s 轮询
- **响应式**：移动端垂直堆叠，隐藏非关键列

### API

| 端点 | 方法 | 参数 | 返回 |
|------|------|------|------|
| `/` | GET | — | HTML 页面 |
| `/health` | GET | — | `{"status":"ok"}` |
| `/api/all` | GET | — | `{system, processes}` |
| `/api/tail` | GET | `file`, `cursor`, `max_lines` | `{lines, next_cursor, file_size}` |
| `/api/log-status` | GET | — | 日志文件大小信息 |
| `/api/kill` | GET | `pid` | `{ok, pid}` |
| `/api/run` | GET | `cmd` | `{ok, stdout, stderr}` |

`/api/tail` 支持增量读取：首次 `cursor=0` 读最后 N 行，后续传入上次的 `next_cursor` 只读新增行。

`/api/all` 返回示例：

```json
{
  "system": {
    "cpu": {"percent": 12.5, "count": 12, "freq_current": 2400.0},
    "memory": {"total_gb": 16.0, "used_gb": 10.2, "percent": 64.0, ...},
    "disk": {"total_gb": 256.0, "used_gb": 128.0, "percent": 50.0},
    "network": {"sent_mb": 1234.5, "recv_mb": 5678.9},
    "temps": {"coretemp": 45.0},
    "uptime_seconds": 86400
  },
  "processes": [
    {"pid": 123, "name": "python3", "cpu_percent": 5.2, "mem_rss_mb": 200.5, ...}
  ]
}
```

### 文件

```
monitor/
├── hermes-monitor-server.py   # Python 后端（纯标准库 + psutil）
├── hermes-monitor.html        # HTML 前端（Chart.js CDN）
├── 图标.ico                   # Favicon
└── 硬件进程网页图标.ico        # 备用图标
```

---

## 端口诊断 (8920)

### 功能

- 实时检测 4 个端口（8787/9119/8900/8920）的 PROXY/FW/HTTP 三项状态
- 单端口修复 / 一键修复全部
- WSL 网络修复（netsh winsock reset + int ip reset + shutdown）
- 任务序列：① WSL_Start_Hermes → ② Hermes_Port_Forward → ③ 验证端口

### API

| 端点 | 说明 |
|------|------|
| `/api/status` | 端口状态检测 |
| `/api/repair-all` | 修复全部端口 |
| `/api/repair-wsl` | 修复 WSL 网络错误 0x8007054f |
| `/api/start-hermes` | 运行 `~/start_hermes.sh` |
| `/api/port-forward` | 运行 `port_forward_hermes.ps1` |

### 文件

```
port-diag/
├── hermes-diag-server.py   # Python 后端
└── hermes-diag.html        # HTML 前端
```

---

## 部署

### 启动

```bash
bash ~/start_hermes.sh
```

### Windows 端口转发

```powershell
# 管理员 PowerShell
powershell -ExecutionPolicy Bypass -File "C:\Users\77630\port_forward_hermes.ps1"
```

转发端口：8787 → 9119 → 8900 → 8920

## 技术栈

- **后端**：Python 3.11 + `http.server` + `psutil`
- **前端**：原生 HTML/CSS/JS + Chart.js 4.4
- **日志**：反向读取大文件（139MB+），支持增量轮询
- **兼容**：WSL2 + Windows，移动端响应式

## 相关仓库

| 仓库 | 说明 |
|------|------|
| [Hermes_Monitoring](https://github.com/yuchen1017918/Hermes_Monitoring) | 统一监控面板 |
| ~~[Hermes_Process](https://github.com/yuchen1017918/Hermes_Process)~~ | 已合并，不再维护 |
