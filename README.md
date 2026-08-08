# Hermes Agent 本地环境

> Hermes Agent 在 WSL2 + Windows 双平台上的完整本地运行套件：一键启动全家桶、实时监控 Hermes 进程/硬件/日志、服务故障一键诊断修复。

![](https://img.shields.io/badge/Python-3.11-blue) ![](https://img.shields.io/badge/平台-WSL2%20%2B%20Windows-green) ![](https://img.shields.io/badge/端口-8787%2C9119%2C8900%2C8921-orange)

## 简介

本仓库是 **Hermes Agent 本地环境的一站式运维套件**，包含：

| 组件 | 端口 | 角色 | 文件 |
|------|------|------|------|
| **统一监控面板** | 8900 | 监控 Hermes 进程、硬件资源（CPU/内存/磁盘/温度）与日志报错 | `hermes-monitor-server.py` + `hermes-monitor.html` |
| **诊断面板** | 8921 | 独立 WebUI（Windows 侧运行）：检测 WebUI/仪表盘/统一监控是否启动，一键诊断修复 | `hermes-diag-server.py` + `hermes-diag.html` |
| **全栈启动脚本** | — | 一键启动 Hermes 全栈（WebUI + Gateway + Dashboard + 监控 + Windows 侧诊断面板） | `start_hermes.sh` |
| **端口转发脚本** | — | Windows 侧将 WSL2 服务端口映射到局域网，手机可访问 | `port_forward_hermes.ps1` |
| **温度读取脚本** | — | 通过 LibreHardwareMonitor 读取 CPU/GPU 温度（HWiNFO 共享内存的备用方案） | `read_temp.ps1` + `librehardwaremonitor/` |
| **自动升级检查** | — | 定时检测 HermesAgent/hermes-webui 上游更新并自动 pull --rebase | `upgrade_check.sh` |
| **诊断面板启动器** | 8921 | Windows 侧开机自启诊断面板（WSL 网络故障时仍可用） | `start_diag_win.bat` + `start_diag_win.vbs` |
| **HWiNFO 续期脚本** | — | 定时重启 HWiNFO64 续期共享内存（绕过免费版 12h 限制） | `renew_hwinfo.ps1` |
| **任务计划模板** | — | Windows 任务计划程序 XML（含占位符，导入前需替换） | `task-scheduler/*.xml` |
| **任务计划安装器** | — | 自动探测本机信息、替换占位符并导入任务计划 | `install_tasks.ps1` |
| **WSL 探测脚本** | — | 自动探测 WSL 发行版/用户名（UTF-16 编码兼容） | `detect_wsl.ps1` |

> 🚀 **零配置部署**：所有脚本均无硬编码路径/用户名，通过环境变量或自动探测适配任意机器。

---

## 快速开始

### 1. 克隆仓库

```bash
# WSL 内任意位置（建议 ~/workspace/）
git clone https://github.com/yuchen1017918/hermes-local-env.git
cd hermes-local-env
```

### 2. 一键导入任务计划（Windows 侧，管理员 PowerShell）

```powershell
cd 仓库所在目录
powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1          # 实际导入
powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1 -DryRun  # 预览不导入
```

安装器自动完成：
1. 探测本机信息（Windows 用户名 / 机器名 / WSL 发行版 / WSL 用户名）
2. 将 `task-scheduler/*.xml` 模板中的 `{{占位符}}` 替换为实际值
3. 生成 UTF-16 XML 并通过 `schtasks /Create` 导入

> 也可手动导入：将 `task-scheduler/*.xml` 中的 `{{WIN_USER}}` `{{WIN_PROFILE}}` `{{COMPUTER}}` `{{WSL_DISTRO}}` `{{WSL_USER}}` `{{WSL_HOME}}` 替换为实际值后，在任务计划程序中「导入任务」。

### 3. 手动启动

```bash
bash start_hermes.sh          # WSL 侧全栈（含拉起 Windows 侧诊断面板）
```

```bat
:: Windows 侧手动启动诊断面板（双击即可）
start_diag_win.bat            :: 启动后访问 http://localhost:8921
```

```powershell
# 管理员 PowerShell 手动端口转发
powershell -ExecutionPolicy Bypass -File .\port_forward_hermes.ps1
```

---

## Hermes Agent 统一监控面板 (8900)

**职责：监控 Hermes 进程的硬件占用与日志报错，一屏掌握运行健康度。**

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
│  123  hermes 5% 200M  │  │                            │
│  456  python  2% 80M  │  │                            │
│  789  node    1% 50M  │  │                            │
└──────────────────────┴──┴────────────────────────────┘
        ◄── 分割线可拖动 (20%~65%) ──►
```

### 功能

**左侧 · 系统与进程**
- 仪表盘：CPU/内存/磁盘/SWAP 实时百分比 + 进度条
- 趋势图：CPU 和内存 60 点折线趋势（Chart.js）
- 温度：CPU/GPU 真实温度，三级数据源自动降级
  - ① HWiNFO 共享内存（官方 API，优先）
  - ② HWiNFO CSV 日志（动态定位 Tctl/GPU 列，可用环境变量 `HWINFO_LOG` 覆盖）
  - ③ Windows ACPI（估算值兜底）
- 进程表：匹配 `hermes` / `bootstrap.py` 等 Hermes 相关进程，支持排序、Kill、重新启动

**右侧 · 日志报错**
- Gateway 日志 + Web UI 日志，Tab 切换
- 大文件反向读取（139MB+），增量轮询，关键词实时过滤
- 行数选择：200/500/1000/2000 行

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

`/api/all` 返回示例：

```json
{
  "system": {
    "cpu": {"percent": 12.5, "count": 12, "freq_current": 2400.0},
    "memory": {"total_gb": 16.0, "used_gb": 10.2, "percent": 64.0, ...},
    "disk": {"total_gb": 256.0, "used_gb": 128.0, "percent": 50.0},
    "network": {"sent_mb": 1234.5, "recv_mb": 5678.9},
    "temps": {"coretemp": 45.0},
    "cpu_temp_c": 58.3, "gpu_temp_c": 57.1, "temp_source": "hwinfo",
    "uptime_seconds": 86400
  },
  "processes": [
    {"pid": 123, "name": "python3", "cpu_percent": 5.2, "mem_rss_mb": 200.5, ...}
  ]
}
```

---

## Hermes Agent 诊断面板 (8921)

**职责：独立 WebUI（运行于 Windows 侧）——检测 Hermes 三大服务（WebUI / Dashboard / 统一监控）是否启动，提供一键诊断与修复。WSL 网络故障时面板依然可用。**

> 诊断面板运行于 Windows 侧（8921），不依赖 WSL 网络状态；曾运行于 WSL 侧，现已废弃。

### 功能

- **端口状态检测**：实时检测 3 个核心服务端口，每项三指标
  - `PROXY`：netsh portproxy 转发规则是否存在
  - `FW`：Windows 防火墙放行规则是否启用
  - `HTTP`：`/health` 探活是否返回 2xx/3xx

| 端口 | 服务 |
|------|------|
| 8787 | WebUI |
| 9119 | Dashboard |
| 8900 | 统一监控 |

- **一键修复全部端口**：重建 portproxy + 防火墙规则
- **修复 WSL 网络**：`netsh winsock reset` + `netsh int ip reset all` + WSL 重启（解决 0x8007054f）
- **一键启动 Hermes**：调用 `start_hermes.sh`
- **端口转发**：调用 `port_forward_hermes.ps1`
- **内置 Web 终端**：PowerShell / CMD / WSL 三种终端，可直接执行任意命令排查

### API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/status` | GET | 端口状态检测 |
| `/api/repair-all` | GET | 修复全部端口 |
| `/api/repair-wsl` | GET | 修复 WSL 网络错误 0x8007054f |
| `/api/start-hermes` | GET | 运行 `start_hermes.sh` |
| `/api/port-forward` | GET | 运行 `port_forward_hermes.ps1` |
| `/api/terminal` | POST | Web 终端执行 `{term: powershell\|cmd\|wsl, cmd}` |

### 双平台自动探测

诊断面板与启动器通过以下机制实现**零硬编码**：

| 本机信息 | 探测方式 | 可覆盖环境变量 |
|----------|----------|----------------|
| Windows 用户目录 | `USERPROFILE` / WSL 侧扫描 `/mnt/c/Users` | `HERMES_WIN_USER_DIR` |
| WSL 发行版 | `detect_wsl.ps1`（.NET 字节流解码 UTF-16） | `WSL_DISTRO` |
| WSL 用户名 | `wsl whoami` | `WSL_USER` |
| 仓库路径 | 脚本自身位置 `%~dp0` / `dirname $0` 推导 | `MONITOR_UNC` |
| HWiNFO 目录 | `%USERPROFILE%\hwinfo` | `HWINFO_DIR` |

---

## 任务计划程序

Windows 侧自动化由**任务计划程序**统一调度。模板位于 `task-scheduler/*.xml`，用 `install_tasks.ps1` 一键导入：

| 任务名 | 触发器 | 执行内容 | 作用 |
|--------|--------|----------|------|
| `WSL_Start_Hermes` | 登录时 | `wsl -d {{WSL_DISTRO}} -u {{WSL_USER}} {{WSL_HOME}}/start_hermes.sh` | 登录后自动启动 Hermes 全栈 |
| `HermesDiagPanel` | 登录时 | `cmd /c start_diag_win.bat` | 登录后自动启动 Windows 侧诊断面板（8921） |
| `Hermes_Port_Forward` | 登录时 | `powershell port_forward_hermes.ps1`（隐藏窗口） | 登录后自动配置端口转发 + 防火墙 |
| `Hermes-HWiNFO` | 登录时 | 启动 `HWiNFO64.exe`（隐藏窗口，常驻） | 保证监控面板温度数据源 |
| `Hermes-HWiNFO-Renew` | 每 1 小时 | `powershell renew_hwinfo.ps1` | 续期 HWiNFO 共享内存 12h 限制 |
| `升级hermes` | 每天 07:00 起 | `wsl upgrade_check.sh`（输出追加到 upgrade.log） | 每日自动检查并升级 HermesAgent/hermes-webui |
| `启动 xEdge 干将互联` | 登录时 | 启动第三方 AI 终端（非 Hermes 核心） | 登录后自动启动 |

### install_tasks.ps1 说明

```powershell
# 管理员 PowerShell
powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1          # 实际导入
powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1 -DryRun  # 预览不导入
```

- 自动探测 Windows 用户 / 机器名 / WSL 发行版 / WSL 用户名
- 将 XML 模板占位符替换为实际值 → 生成 UTF-16 XML → `schtasks /Create` 导入
- 支持环境变量覆盖：`WIN_USER` `WSL_DISTRO` `WSL_USER` `MONITOR_UNC`

---

## 运维脚本详解

### `start_hermes.sh` — Hermes 全栈一键启动

WSL 侧启动脚本（登录时由 `WSL_Start_Hermes` 任务触发，或手动执行），按序拉起完整 Hermes 环境：

0. **单实例保护 + 残留清理**：`flock` 防重复启动；清理 8787/9119/8900 残留进程（诊断面板已迁 Windows 侧 8921，无需处理）
1. **路径自定位**：仓库路径由脚本自身位置推导（可放任意目录）；Hermes-Agent 安装目录默认 `$HOME/Hermes-Agent`（环境变量 `HERMES_AGENT_DIR` 覆盖）
2. **环境加固**：加载 `~/.bash_profile` / `~/.bashrc`，补齐 PATH
3. **等待 C 盘挂载**：自动识别 Windows 用户名，将 WSL IP 写入 `C:\Users\<user>\wsl_ip.txt`
4. **Hermes WebUI**（8787）：后台启动 `bootstrap.py`，日志 `~/hermes_webui.log`
5. **Hermes Gateway**：Tmux 独立会话 `hermes-gateway` 常驻，日志 `~/hermes_gateway.log`
6. **Hermes Dashboard**（9119）：`hermes dashboard --no-open`，日志 `~/.hermes/dashboard.log`
7. **统一监控面板**（8900）：`hermes-monitor-server.py`，日志 `~/.hermes/monitor.log`
8. **诊断面板**（Windows 侧 8921）：调用 `cmd /c start_diag_win.bat` 拉起，日志 `diag_win.log`

每步均有进程存活校验与失败提示，可重复执行（已运行的服务自动跳过）。

### `start_diag_win.bat` + `start_diag_win.vbs` — Windows 侧诊断面板启动器

Windows 侧启动脚本（登录时由 `HermesDiagPanel` 任务触发，或由 `start_hermes.sh` 调用）：

1. 检测端口 8921 是否已在监听，已运行则跳过
2. 通过 `detect_wsl.ps1` 自动探测 WSL 发行版/用户名（UTF-16 编码兼容）
3. 等待 WSL 文件系统就绪（UNC 路径可达，最长 30s）
4. vbs 以隐藏窗口启动 `hermes-diag-server.py`（端口 8921），不依赖 WSL 网络
5. 运行日志写入 `%USERPROFILE%\diag_launcher.log`

### `detect_wsl.ps1` — WSL 探测脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\detect_wsl.ps1            # 输出: distro 和 user 两行
powershell -NoProfile -ExecutionPolicy Bypass -File .\detect_wsl.ps1 -DistroOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\detect_wsl.ps1 -UserOnly
```

> 解决 `wsl -l -q` 输出 UTF-16LE 导致管道乱码的问题（.NET 字节流解码）。

### `port_forward_hermes.ps1` — 局域网端口转发

Windows 侧脚本（需管理员权限）：自动获取 WSL2 IP，为 8787/9119/8900 配置 netsh portproxy + 防火墙放行；另为 Windows 侧诊断面板 8921 单独放行防火墙（直连无需转发）。手机/局域网设备可直接访问。

### `upgrade_check.sh` — Hermes 自动升级检查

定时任务（由 Windows 任务计划 `升级hermes` 触发，每天 07:00 起），检测 HermesAgent 及其 hermes-webui 子模块的上游更新并自动升级：

1. **拉取上游**：`git fetch origin main/master`（60s 超时保护，国内网络友好）
2. **计算差距**：`rev-list --count` 统计 behind/ahead
3. **有更新则升级**：`git pull --rebase` 保留本地提交
4. **安全兜底**：`flock` 防并发执行；rebase 冲突自动 `abort` 回滚，绝不 `reset --hard`
5. **结果落盘**：输出追加写入 `~/.hermes/scripts/upgrade.log`

### `renew_hwinfo.ps1` — HWiNFO 共享内存续期

Windows 计划任务（`Hermes-HWiNFO-Renew`，每小时运行），解决 HWiNFO 免费版 **共享内存 12 小时过期限制**：

- HWiNFO64 运行超过 10.5h → 强制重启（共享内存计时重新开始）
- HWiNFO64 未运行（异常退出）→ 自动重新拉起
- HWiNFO 安装目录：默认 `%USERPROFILE%\hwinfo`，可用环境变量 `HWINFO_DIR` 覆盖

---

## 部署

### 访问

| 服务 | 本机 | 局域网 |
|------|------|--------|
| WebUI | http://localhost:8787 | http://<局域网IP>:8787 |
| Dashboard | http://localhost:9119 | http://<局域网IP>:9119 |
| 统一监控 | http://localhost:8900 | http://<局域网IP>:8900 |
| 诊断面板 | http://localhost:8921 | http://<局域网IP>:8921 |

### 前置依赖

| 依赖 | 说明 |
|------|------|
| Python 3.11+ | `psutil`（监控后端）、Windows 侧需 `pythonw.exe` 可访问 |
| Hermes Agent | 安装于 `~/Hermes-Agent/`（或设置 `HERMES_AGENT_DIR`） |
| HWiNFO64 | 安装于 `%USERPROFILE%\hwinfo\`（温度数据源，可选） |
| WSL2 | 任一发行版（`detect_wsl.ps1` 自动探测） |

---

## 文件结构

```
hermes-local-env/
├── hermes-monitor-server.py   # 统一监控面板后端（Python http.server + psutil）
├── hermes-monitor.html        # 统一监控面板前端（Chart.js CDN）
├── hermes-diag-server.py      # 诊断修复面板后端（Windows 侧 8921，双平台适配）
├── hermes-diag.html           # 诊断修复面板前端
├── start_hermes.sh            # Hermes 全栈一键启动（WSL 侧，路径自定位）
├── start_diag_win.bat         # Windows 侧诊断面板启动器（8921）
├── start_diag_win.vbs         # 隐藏窗口拉起诊断面板（自动探测 pythonw）
├── detect_wsl.ps1             # WSL 发行版/用户名探测（UTF-16 兼容）
├── install_tasks.ps1          # 任务计划一键导入（占位符替换 + schtasks）
├── upgrade_check.sh           # Hermes 自动升级检查（每日定时）
├── renew_hwinfo.ps1           # HWiNFO 共享内存 12h 限制续期（每小时）
├── port_forward_hermes.ps1    # Windows 端口转发（局域网访问）
├── read_temp.ps1              # LibreHardwareMonitor 温度读取脚本
├── librehardwaremonitor/      # LibreHardwareMonitor 运行时依赖库
├── task-scheduler/            # Windows 任务计划程序 XML 模板（{{占位符}}）
│   ├── WSL_Start_Hermes.xml       # 登录自启 Hermes 全栈
│   ├── HermesDiagPanel.xml        # 登录自启诊断面板（8921）
│   ├── Hermes_Port_Forward.xml    # 登录自启端口转发
│   ├── Hermes-HWiNFO.xml          # 登录自启 HWiNFO64
│   ├── Hermes-HWiNFO-Renew.xml    # 每小时续期共享内存
│   ├── 升级hermes.xml             # 每日 07:00 自动升级检查
│   └── 启动 xEdge 干将互联.xml    # 登录自启第三方 AI 终端
├── 图标.ico                   # 统一监控 Favicon
└── 硬件进程网页图标.ico        # 诊断面板 Favicon
```

## 技术栈

- **后端**：Python 3.11 + `http.server` + `psutil`（零第三方依赖）
- **前端**：原生 HTML/CSS/JS + Chart.js 4.4（CDN）
- **日志**：大文件反向读取 + 增量轮询
- **温度**：HWiNFO 共享内存 > HWiNFO CSV > LibreHardwareMonitor / Windows ACPI 兜底
- **兼容**：WSL2 + Windows（诊断面板独立运行于 Windows 侧），移动端响应式
- **自动化**：Windows 任务计划程序（XML 模板 + 一键导入）统一调度开机自启与定时任务
- **零硬编码**：所有路径/用户名通过环境变量覆盖或自动探测

## 相关仓库

| 仓库 | 说明 |
|------|------|
| [hermes-local-env](https://github.com/yuchen1017918/hermes-local-env) | 本仓库（原 Hermes_Monitoring 迁移更名）：Hermes Agent 本地环境套件（统一监控 + 诊断修复 + 自启脚本 + 任务计划） |
| [vibe-skill-ops](https://github.com/yuchen1017918/vibe-skill-ops) | Vibe Coding skill 体系（三层路由、知识萃取、成本治理） |
