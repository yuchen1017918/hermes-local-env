# Hermes-Local-Env 本地环境套件安装教程（Agent 版）

> 本教程写给 **AI Agent**（Hermes Agent / Claude Code / Codex / 其他支持命令行与脚本执行的 Agent）。
> 目标：在目标机器（WSL2 + Windows 双平台）上安装并启动 **Hermes Agent 本地环境套件**（统一监控 8900 + 诊断面板 8921 + 一键启动 + 任务计划自动运维）。
>
> 用户可以直接把下面的提示词发给 Agent，Agent 会按本教程执行：
> `https://yuchen1017918.github.io/hermes-local-env/Tutorial.md，帮我下载安装这个 hermes 环境。`
> （GitHub Pages 未启用前，用 raw 地址：`https://raw.githubusercontent.com/yuchen1017918/hermes-local-env/main/Tutorial.md`）

---

## 一、这是什么

`hermes-local-env` 是 Hermes Agent 在 **WSL2 + Windows 双平台**上的一站式本地运维套件：

- **统一监控面板**（8900）：监控 Hermes 进程、硬件资源（CPU/内存/磁盘/温度）、Gateway/WebUI 日志报错
- **诊断修复面板**（8921）：独立运行于 Windows 侧（WSL 网络故障仍可用），一键诊断修复 WebUI/Dashboard/监控服务
- **全栈启动脚本**：一键拉起 WebUI(8787) + Gateway + Dashboard(9119) + 监控(8900) + Windows 侧诊断(8921)
- **端口转发**：WSL2 服务 → 局域网，手机可直接访问
- **任务计划自动运维**：7 个 Windows 任务计划（登录自启、每日升级检查、HWiNFO 续期）
- **零硬编码**：所有路径/用户名通过自动探测或环境变量覆盖，克隆即用

> 安装后用户使用：Agent 执行一键启动 → 用户浏览器访问各面板 → 故障时打开诊断面板一键修复。

## 二、安装前置条件

| 条件 | 说明 |
|------|------|
| WSL2 已启用 | 任一发行版（脚本自动探测发行版与用户名） |
| Windows 10/11 | 与 WSL2 同机 |
| Python 3.8+ | WSL 内可用（`python3 --version` 验证） |
| `psutil` 库 | 监控后端依赖（`pip3 install psutil`，见 §三 步骤 3） |
| HWiNFO64（可选） | 安装于 `%USERPROFILE%\hwinfo\`，提供真实温度数据源 |
| Hermes Agent（可选） | 若机器已有 Hermes Agent，监控面板可监控其进程；无则监控面板仅显示系统资源 |

## 三、下载安装（4 步）

### 方式 A：git clone（推荐，WSL 内执行）

```bash
# 1. 下载仓库（国内网络慢可用 ghproxy 前缀，见 §五）
git clone https://github.com/yuchen1017918/hermes-local-env.git ~/hermes-local-env
cd ~/hermes-local-env

# 2. 安装 Python 依赖（仅监控面板需要 psutil）
pip3 install psutil 2>/dev/null || pip install psutil

# 3. 语法自检（应无输出）
python3 -m py_compile hermes-monitor-server.py hermes-diag-server.py

# 4. 一键启动全栈（WebUI/Gateway/Dashboard 不存在时自动跳过，仅拉起监控+诊断）
bash start_hermes.sh
```

### 方式 B：下载 zip（无 git 环境）

```bash
cd /tmp
curl -L -o hermes-local-env.zip https://github.com/yuchen1017918/hermes-local-env/archive/refs/heads/main.zip
unzip -o hermes-local-env.zip
cd hermes-local-env-main
# 后续步骤同上（pip install psutil → bash start_hermes.sh）
```

## 四、Windows 侧部署（任务计划 + 诊断面板，管理员 PowerShell）

```powershell
# 1. 进入仓库目录（WSL 视角的 Windows UNC 路径，如 \\wsl.localhost\Ubuntu-22.04\home\<user>\hermes-local-env）
cd \\wsl.localhost\<发行版>\home\<用户>\hermes-local-env

# 2. 一键导入 7 个任务计划（自动探测本机信息 + 替换占位符 + schtasks 导入）
powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1

# 3. 可选：先预览不导入
powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1 -DryRun
```

> 若无法从 UNC 路径运行，可先将仓库复制到 Windows 侧（如 `C:\hermes-local-env`），再执行上述命令。

## 五、验证安装（必须做）

1. **监控面板**：浏览器访问 `http://localhost:8900` → 应看到系统仪表盘 + 进程表 + 日志区
2. **诊断面板**：浏览器访问 `http://localhost:8921` → 应看到三大服务端口状态检测
3. **任务计划**（Windows）：`taskschd.msc` → 任务计划程序库 → 应看到 `WSL_Start_Hermes` / `HermesDiagPanel` / `Hermes_Port_Forward` / `Hermes-HWiNFO` / `Hermes-HWiNFO-Renew` / `升级hermes` / `启动 xEdge 干将互联`
4. **进程**：`pgrep -f "hermes-monitor-server|hermes-diag-server"` 应返回 PID

**未通过验证 → 不要声称安装成功**，先看 §七 排障。

## 六、国内网络加速

```bash
# git clone 慢 → ghproxy 前缀
git clone https://ghproxy.net/https://github.com/yuchen1017918/hermes-local-env.git ~/hermes-local-env

# 或 zip 走镜像
curl -L -o hermes-local-env.zip https://ghproxy.net/https://github.com/yuchen1017918/hermes-local-env/archive/refs/heads/main.zip
```

## 七、常见故障排查

| 症状 | 原因 | 处理 |
|------|------|------|
| 监控面板打不开 8900 | psutil 未装 / 端口被占 | `pip3 install psutil`；`lsof -ti:8900` 查占用 |
| 诊断面板 8921 打不开 | Windows 侧 pythonw 未装 / 启动器未部署 | 确认 Python 已装；重跑 `install_tasks.ps1`（会部署 start_diag_win.vbs 等） |
| 温度显示 N/A | HWiNFO 未运行 / 未装 | 安装 HWiNFO64 到 `%USERPROFILE%\hwinfo\`；或接受 ACPI 估算值 |
| start_hermes.sh 报 WebUI 目录不存在 | 未安装 Hermes Agent | 忽略即可（该步自动跳过）；或先安装 Hermes Agent |
| install_tasks.ps1 报无法探测 WSL | wsl.exe 输出编码 | 设置环境变量 `WSL_DISTRO` / `WSL_USER` 后重试 |
| clone 超时 | 国内网络 | 用 §六 镜像前缀 |
| 任务计划导入失败 | 权限不足 | 以**管理员身份**运行 PowerShell |

## 八、安装完成后第一件事（Agent 必做）

1. 验证两个面板可访问（§五 步骤 1-2）
2. 向用户说明：**「Hermes 本地环境套件安装完成：监控面板 http://localhost:8900 · 诊断面板 http://localhost:8921」**
3. 提示用户可查看网页版介绍：`https://yuchen1017918.github.io/hermes-local-env/`

## 九、更新与卸载

```bash
# 更新（覆盖式）
cd ~/hermes-local-env && git pull
bash start_hermes.sh

# 卸载
pkill -f "hermes-monitor-server|hermes-diag-server" 2>/dev/null
rm -rf ~/hermes-local-env
# Windows 侧删除任务计划（管理员 PowerShell）：
#   schtasks /Delete /TN WSL_Start_Hermes /F
#   schtasks /Delete /TN HermesDiagPanel /F
#   schtasks /Delete /TN Hermes_Port_Forward /F
#   schtasks /Delete /TN Hermes-HWiNFO /F
#   schtasks /Delete /TN Hermes-HWiNFO-Renew /F
#   schtasks /Delete /TN 升级hermes /F
#   schtasks /Delete /TN "启动 xEdge 干将互联" /F
```

---

*本仓库：https://github.com/yuchen1017918/hermes-local-env · MIT License · v1.0.0*
