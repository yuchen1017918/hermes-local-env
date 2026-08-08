# Hermes Agent 本地环境

> Hermes Agent 在 WSL2 + Windows 双平台上的完整本地运行套件：一键启动全家桶、实时监控 Hermes 进程/硬件/日志、服务故障一键诊断修复。

![](https://img.shields.io/badge/Python-3.11-blue) ![](https://img.shields.io/badge/平台-WSL2%20%2B%20Windows-green) ![](https://img.shields.io/badge/端口-8787%2C9119%2C8900%2C8921-orange)

## 组件总览

| 组件 | 端口 | 角色 | 文件 |
|------|------|------|------|
| **Hermes Agent 统一监控面板** | 8900 | 监控 Hermes 进程、硬件资源（CPU/内存/磁盘/温度）与日志报错 | `hermes-monitor-server.py` + `hermes-monitor.html` |
| **Hermes Agent 诊断面板** | 8921 | 独立 WebUI（Windows 侧运行）：检测 WebUI/仪表盘/统一监控是否启动，一键诊断修复 | `hermes-diag-server.py` + `hermes-diag.html` |
| **开机自启脚本** | — | 一键启动 Hermes 全栈（WebUI + Gateway + Dashboard + 监控 + Windows 侧诊断面板） | `start_hermes.sh` |
| **端口转发脚本** | — | Windows 侧将 WSL2 服务端口映射到局域网，手机可访问 | `port_forward_hermes.ps1` |
| **温度读取脚本** | — | 通过 LibreHardwareMonitor 读取 CPU/GPU 温度（HWiNFO 共享内存的备用方案） | `read_temp.ps1` + `librehardwaremonitor/` |
| **自动升级检查** | — | 定时检测 HermesAgent/hermes-webui 上游更新并自动 pull --rebase | `upgrade_check.sh` |
| **Windows 诊断启动器** | 8921 | Windows 侧开机自启诊断面板（WSL 网络故障时仍可用） | `start_diag_win.bat` |
| **HWiNFO 续期脚本** | — | 定时重启 HWiNFO64 续期共享内存（绕过免费版 12h 限制） | `renew_hwinfo.ps1` |
| **任务计划程序** | — | Windows 侧全部开机自启/定时任务的 XML 定义（可一键导入） | `task-scheduler/*.xml` |

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
  - ② HWiNFO CSV 日志（动态定位 Tctl/GPU 列）
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

> 诊断面板曾运行于 WSL 侧，现已废弃，统一迁移至 Windows 侧 8921（`start_diag_win.bat` 拉起），与 WSL 侧服务互不依赖。

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
- **一键启动 Hermes**：调用 `~/start_hermes.sh`
- **端口转发**：调用 `port_forward_hermes.ps1`
- **内置 Web 终端**：PowerShell / CMD / WSL 三种终端，可直接执行任意命令排查

### API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/status` | GET | 端口状态检测 |
| `/api/repair-all` | GET | 修复全部端口 |
| `/api/repair-wsl` | GET | 修复 WSL 网络错误 0x8007054f |
| `/api/start-hermes` | GET | 运行 `~/start_hermes.sh` |
| `/api/port-forward` | GET | 运行 `port_forward_hermes.ps1` |
| `/api/terminal` | POST | Web 终端执行 `{term: powershell\|cmd\|wsl, cmd}` |

---

## 任务计划程序

Windows 侧自动化由**任务计划程序**统一调度，全部任务定义在 `task-scheduler/*.xml`（通过「任务计划程序 → 导入任务」一键恢复）：

| 任务名 | 触发器 | 执行内容 | 作用 |
|--------|--------|----------|------|
| `WSL_Start_Hermes` | 登录时 | `wsl -d Ubuntu-22.04 -u yuchen_wang /home/yuchen_wang/start_hermes.sh` | 登录后自动启动 Hermes 全栈 |
| `HermesDiagPanel` | 登录时 | `cmd /c start_diag_win.bat` | 登录后自动启动 Windows 侧诊断面板（8921） |
| `Hermes_Port_Forward` | 登录时 | `powershell port_forward_hermes.ps1`（隐藏窗口） | 登录后自动配置端口转发 + 防火墙 |
| `Hermes-HWiNFO` | 登录时 | 启动 `HWiNFO64.exe`（隐藏窗口，常驻） | 保证监控面板温度数据源 |
| `Hermes-HWiNFO-Renew` | 每 1 小时 | `powershell renew_hwinfo.ps1` | 续期 HWiNFO 共享内存 12h 限制 |
| `升级hermes` | 每天 07:00 起 | `wsl upgrade_check.sh`（输出追加到 upgrade.log） | 每日自动检查并升级 HermesAgent/hermes-webui |
| `启动 xEdge 干将互联` | 登录时 | 启动 `C:\Program Files\xedge-tui\xEdge干将互联.exe` | 登录后自动启动第三方 AI 终端（非 Hermes 核心） |

> 这些 XML 由「任务计划程序 → 导入任务」使用；用户名、路径按实际环境微调后即可恢复整套自动运维。

---

## 开机自启与运维脚本

### `start_hermes.sh` — Hermes 全栈一键启动

WSL 侧启动脚本（登录时由 `WSL_Start_Hermes` 任务触发），按序拉起完整 Hermes 环境：

0. **单实例保护 + 残留清理**：`flock` 防重复启动；清理 8787/9119/8900 残留进程（诊断面板已迁 Windows 侧 8921，无需处理）
1. **环境加固**：加载 `~/.bash_profile` / `~/.bashrc`，补齐 PATH
2. **等待 C 盘挂载**：自动识别 Windows 用户名，将 WSL IP 写入 `C:\Users\<user>\wsl_ip.txt`（供端口转发脚本读取）
3. **Hermes WebUI**（8787）：后台启动 `bootstrap.py`，日志 `~/hermes_webui.log`
4. **Hermes Gateway**：Tmux 独立会话 `hermes-gateway` 常驻，日志 `~/hermes_gateway.log`
5. **Hermes Dashboard**（9119）：`hermes dashboard --no-open`，日志 `~/.hermes/dashboard.log`
6. **统一监控面板**（8900）：`hermes-monitor-server.py`，日志 `~/.hermes/monitor.log`
7. **诊断面板**（Windows 侧 8921）：调用 `cmd /c start_diag_win.bat` 拉起（WSL 网络故障时仍可用），日志 `C:\Users\77630\diag_win.log`

每步均有进程存活校验与失败提示，可重复执行（已运行的服务自动跳过）。

### `start_diag_win.bat` — Windows 侧诊断面板启动器

Windows 侧启动脚本（登录时由 `HermesDiagPanel` 任务触发，或由 `start_hermes.sh` 第 7 步调用）：

1. 检测端口 8921 是否已在监听，已运行则跳过
2. 等待 WSL 文件系统就绪（UNC 路径可达，最长 30s）
3. 通过 `wscript` 拉起 `start_diag_win.vbs` → 在 Windows 侧启动 `hermes-diag-server.py`（端口 8921）
4. 运行日志写入 `C:\Users\77630\diag_launcher.log`

> 诊断面板运行于 Windows 侧（8921），不依赖 WSL 网络状态；WSL 故障时仍可诊断与修复。

### `port_forward_hermes.ps1` — 局域网端口转发

Windows 侧脚本（需管理员权限）：自动获取 WSL2 IP，为 8787/9119/8900 配置 netsh portproxy + 防火墙放行；另为 Windows 侧诊断面板 8921 单独放行防火墙（直连无需转发）。手机/局域网设备可直接访问。

### `read_temp.ps1` + `librehardwaremonitor/` — 温度读取

通过 LibreHardwareMonitorLib.dll 枚举 CPU/GPU 温度传感器，作为 HWiNFO 共享内存不可用时的备用温度源。

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

> 配合统一监控面板温度源：HWiNFO 共享内存持续可用，面板才能拿到真实 CPU/GPU 温度。

---

## 部署

### 一键恢复任务计划

将 `task-scheduler/*.xml` 逐个导入 Windows 任务计划程序（「任务计划程序库 → 导入任务…」），登录后自动完成全部启动/运维；或手动启动：

```bash
bash ~/start_hermes.sh          # WSL 侧全栈（含拉起 Windows 侧诊断面板）
```

```bat
:: Windows 侧手动启动诊断面板
C:\Users\77630\start_diag_win.bat   :: 启动后访问 http://localhost:8921
```

```powershell
# 管理员 PowerShell 手动端口转发
powershell -ExecutionPolicy Bypass -File "C:\Users\77630\port_forward_hermes.ps1"
```

### 访问

| 服务 | 本机 | 局域网 |
|------|------|--------|
| WebUI | http://localhost:8787 | http://<局域网IP>:8787 |
| Dashboard | http://localhost:9119 | http://<局域网IP>:9119 |
| 统一监控 | http://localhost:8900 | http://<局域网IP>:8900 |
| 诊断面板 | http://localhost:8921 | http://<局域网IP>:8921 |

---

## 文件结构

```
monitor/
├── hermes-monitor-server.py   # 统一监控面板后端（Python http.server + psutil）
├── hermes-monitor.html        # 统一监控面板前端（Chart.js CDN）
├── hermes-diag-server.py      # 诊断修复面板后端（Windows 侧 8921）
├── hermes-diag.html           # 诊断修复面板前端
├── start_hermes.sh            # Hermes 全栈一键启动（WSL 侧，登录自启）
├── start_diag_win.bat         # Windows 侧诊断面板启动器（8921）
├── upgrade_check.sh           # Hermes 自动升级检查（每日定时）
├── renew_hwinfo.ps1           # HWiNFO 共享内存 12h 限制续期（每小时）
├── port_forward_hermes.ps1    # Windows 端口转发（局域网访问）
├── read_temp.ps1              # LibreHardwareMonitor 温度读取脚本
├── librehardwaremonitor/      # LibreHardwareMonitor 运行时依赖库
├── task-scheduler/            # Windows 任务计划程序 XML（导入即用）
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
- **自动化**：Windows 任务计划程序（XML 导入）统一调度开机自启与定时任务

## 相关仓库

| 仓库 | 说明 |
|------|------|
| [Hermes_Monitoring](https://github.com/yuchen1017918/Hermes_Monitoring) | Hermes Agent 本地环境（统一监控 + 诊断修复 + 自启脚本 + 任务计划） |
| ~~[Hermes_Process](https://github.com/yuchen1017918/Hermes_Process)~~ | 已合并，不再维护 |
