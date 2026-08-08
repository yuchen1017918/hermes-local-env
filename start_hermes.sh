#!/bin/bash

echo -e "\033[38;5;214m"
cat <<'EOF'
╭────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⣀⣀⠀⢀⣀⡀                [1;37m██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗       █████╗  ██████╗ ███████╗███╗   ██╗████████╗     [38;5;214m│
│  ⠀⠀⠀⠀⠀⠀⢀⣠⣴⣾⣿⣿⣇⠸⣿⣿⠇⣸⣿⣿⣷⣦⣄⡀            [1;37m██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝      ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝     [38;5;214m│
│  ⠀⢀⣠⣴⣶⠿⠋⣩⡿⣿⡿⠻⣿⡇⢠⡄⢸⣿⠟⢿⣿⢿⣍⠙⠿⣶⣦⣄⡀       [1;37m███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗█████╗███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║        [38;5;214m│
│  ⠀⠀⠉⠉⠁⠶⠟⠋⠀⠉⠀⢀⣈⣁⡈⢁⣈⣁⡀⠀⠉⠀⠙⠻⠶⠈⠉⠉        [1;37m██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║╚════╝██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║        [38;5;214m│
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⡿⠛⢁⡈⠛⢿⣿⣦                [1;37m██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║      ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║        [38;5;214m│
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠿⣿⣦⣤⣈⠁⢠⣴⣿⠿               [1;37m╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝      ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝         [38;5;214m│
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠻⢿⣿⣦⡉⠁                                                                                                                           │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢷⣦⣈⠛⠃                                                                                                                            │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣴⠦⠈⠙⠿⣦⡄                                        [38;5;220mHermes-Agent  启动脚本        ~/start_hermes.sh                                    [38;5;214m│
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⣤⡈⠁⢤⣿⠇                                                                                                                           │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠷⠄                                                                                                                             │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠑⢶⣄⡀                                                                                                                            │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠁⢰⡆⠈⡿                                                                                                                            │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠳⠈⣡⠞⠁                                                                                                                            │
│  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈                                                                                                                               │
╰────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
EOF
echo -e "\033[0m"

# 颜色定义
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
CYAN=$'\033[1;36m'
NC=$'\033[0m'

# Hermes-Agent 一体化启动脚本（WebUI + Systemd托管网关）

# ===== 路径自定位（无硬编码，仓库可放任意位置） =====
# 脚本所在目录 = 本仓库目录（monitor/）
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hermes-Agent 安装目录（可用环境变量覆盖）
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-$HOME/Hermes-Agent}"
# Windows 用户目录（可用环境变量覆盖；默认取 /mnt/c/Users 下第一个真实用户）
WIN_USER_DIR="${HERMES_WIN_USER_DIR:-}"
if [ -z "$WIN_USER_DIR" ] && [ -d /mnt/c/Users ]; then
    _win_user=$(ls /mnt/c/Users | grep -v -E '^(Public|Default|All Users)$' | head -n1)
    [ -n "$_win_user" ] && WIN_USER_DIR="/mnt/c/Users/$_win_user"
fi

########################### 单实例检测（只检测一遍） ###########################
# 检测是否已有启动脚本在运行，避免重复启动冲突
LOCK_FILE=/tmp/start_hermes.lock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    # 检查持锁者是否为启动脚本实例（排除自身）；若不是（残留锁），自动清除后继续
    STALE=1
    for p in $(fuser "$LOCK_FILE" 2>/dev/null); do
        [ "$p" = "$$" ] && continue   # 排除当前脚本进程自身
        if ps -p "$p" -o cmd= 2>/dev/null | grep -q "start_hermes"; then
            STALE=0
        fi
    done
    if [ "$STALE" = "1" ]; then
        echo "${YELLOW}⚠️ 检测到残留锁（无启动脚本实例），自动清除后继续${NC}"
        rm -f "$LOCK_FILE"
        exec 9>"$LOCK_FILE"
        if ! flock -n 9; then
            echo "${RED}❌ 仍无法获取锁，请检查后重试${NC}"
            exit 1
        fi
    else
        echo "${YELLOW}⚠️ 已有启动脚本正在运行，请勿重复启动${NC}"
        echo "${CYAN}如需重启请先退出当前运行的启动脚本${NC}"
        exit 1
    fi
fi

########################### 0. 清理残留端口进程 ###########################
# 杀掉占用 WebUI(8787)、网关(9119)、监控面板(8900) 的残留进程（诊断面板已迁Windows侧8921，无需处理）
for PORT in 8787 9119 8900; do
    PIDS=$(ss -tlnp 2>/dev/null | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | sort -u)
    if [ -n "$PIDS" ]; then
        echo "${YELLOW}🔄 端口 $PORT 被残留进程占用，正在清理: $PIDS${NC}"
        kill -9 $PIDS 2>/dev/null
        sleep 1
    fi
done
# 解决关闭WSL终端窗口后网关进程被系统杀死问题

########################### 1. 加固加载完整环境变量 ###########################
# 加载交互式shell环境，补齐hermes、python路径
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi
# 强制补充本地工具路径，避免hermes命令找不到
export PATH="$HOME/.local/bin:$PATH"

########################### 2. 等待Windows C盘挂载 ###########################
WAIT_MOUNT=0
while [ ! -d /mnt/c/Users ]; do
    sleep 1
    WAIT_MOUNT=$((WAIT_MOUNT + 1))
    if [ $WAIT_MOUNT -ge 20 ]; then
        echo "${YELLOW}⚠️ 警告：C盘挂载超时，跳过IP文件写入步骤${NC}"
        break
    fi
done

# 自动获取Windows用户名称、WSL本机IP
if [ -n "$WIN_USER_DIR" ]; then
    WIN_USER=$(basename "$WIN_USER_DIR")
    WSL_IP=$(hostname -I | awk '{print $1}')
    echo "${CYAN}----------------------------------------${NC}"
    echo "${CYAN}当前WSL本机IP: $WSL_IP${NC}"
    echo "${CYAN}Windows登录用户目录: $WIN_USER_DIR${NC}"
    echo "${CYAN}----------------------------------------${NC}"

    # 将WSL IP写入Windows本地文件，供宿主机端口转发脚本读取
    IP_TARGET="${WIN_USER_DIR}/wsl_ip.txt"
    echo "$WSL_IP" > "$IP_TARGET"
    echo "${GREEN}✅ WSL IP已写入Windows文件: $IP_TARGET${NC}"
fi

########################### 3. 启动 Hermes WebUI 后台进程 ###########################
# 切换WebUI项目目录
cd "$HERMES_AGENT_DIR/hermes-webui" || {
    echo "${RED}❌ WebUI目录不存在 $HERMES_AGENT_DIR/hermes-webui，终止启动${NC}"
    exit 1
}

# 启动前清空历史日志，防止日志文件持续膨胀
> ~/hermes_webui.log
echo "${CYAN}正在后台启动 Hermes WebUI 服务...${NC}"
nohup python3 -u bootstrap.py --host 0.0.0.0 --no-browser > ~/hermes_webui.log 2>&1 &

# 循环检测WebUI进程是否启动成功
CHECK_COUNT=0
MAX_CHECK=8
while ! pgrep -f "bootstrap.py" > /dev/null && [ $CHECK_COUNT -lt $MAX_CHECK ]; do
    sleep 1
    CHECK_COUNT=$((CHECK_COUNT + 1))
done

# WebUI启动状态校验
if pgrep -f "bootstrap.py" > /dev/null; then
    echo "${GREEN}✅ Hermes WebUI 后台启动成功，进程持久运行${NC}"
    echo "${CYAN}WebUI日志路径: ~/hermes_webui.log${NC}"
else
    echo "${RED}❌ Hermes WebUI启动失败，请手动执行排查命令：${NC}"
    echo "cd $HERMES_AGENT_DIR/hermes-webui && python3 -u bootstrap.py --host 0.0.0.0 --no-browser"
    exit 2
fi

########################### 4. Tmux 独立会话启动 Hermes Gateway 网关 ###########################
echo -e "${CYAN}\n----------------------------------------${NC}"
echo "${CYAN}使用Tmux后台会话启动Hermes网关（无需systemd，规避启动失败）${NC}"
echo "${CYAN}----------------------------------------${NC}"

# 判断会话是否存在，不存在则新建后台会话
if tmux has-session -t hermes-gateway 2>/dev/null; then
    if pgrep -f "hermes gateway run" > /dev/null; then
        echo "${CYAN}Tmux会话 hermes-gateway 已存在且网关进程存活，无需重复启动${NC}"
    else
        echo "Tmux会话存在但网关进程已死，重建会话..."
        tmux kill-session -t hermes-gateway 2>/dev/null
        tmux new-session -d -s hermes-gateway "hermes gateway run > ~/hermes_gateway.log 2>&1"
        sleep 2
    fi
else
    echo "${CYAN}创建Tmux后台会话 hermes-gateway${NC}"
    # 后台启动网关，日志写入独立文件
    tmux new-session -d -s hermes-gateway "hermes gateway run > ~/hermes_gateway.log 2>&1"
    sleep 2
fi

# 校验网关进程是否运行
if pgrep -f "hermes gateway run" > /dev/null; then
    echo "${GREEN}✅ Hermes Gateway 网关启动成功，Tmux会话永久常驻${NC}"
    echo "${CYAN}网关日志文件：~/hermes_gateway.log${NC}"
    echo "${CYAN}实时查看网关日志命令：tail -f ~/hermes_gateway.log${NC}"
else
    echo "${YELLOW}⚠️ Hermes Gateway 网关启动失败，请查看日志排查${NC}"
    echo "${CYAN}查看日志：tail -n 100 ~/hermes_gateway.log${NC}"
fi

echo -e "${CYAN}\n----------------------------------------${NC}"
echo "${CYAN}启动 Hermes Dashboard 仪表盘...${NC}"
echo "${CYAN}----------------------------------------${NC}"

DASHBOARD_PORT=9119
if lsof -ti:$DASHBOARD_PORT > /dev/null 2>&1; then
    echo "${GREEN}✅ Dashboard 已在运行 (端口 $DASHBOARD_PORT)${NC}"
else
    # --no-open 避免WSL无浏览器时xdg-open报错；首次启动需构建Web UI，循环等待就绪
    nohup hermes dashboard --host 0.0.0.0 --port $DASHBOARD_PORT --no-open > ~/.hermes/dashboard.log 2>&1 &
    DASH_OK=0
    for i in $(seq 1 15); do
        sleep 2
        if lsof -ti:$DASHBOARD_PORT > /dev/null 2>&1; then
            DASH_OK=1
            break
        fi
    done
    if [ $DASH_OK -eq 1 ]; then
        echo "${GREEN}✅ Hermes Dashboard 启动成功${NC}"
        echo "${CYAN}访问地址: http://localhost:$DASHBOARD_PORT${NC}"
    else
        echo "${YELLOW}⚠️ Dashboard 启动失败，查看日志: ~/.hermes/dashboard.log${NC}"
    fi
fi

########################### 6. 启动 Hermes 硬件进程监控 ###########################
echo -e "${CYAN}\n----------------------------------------${NC}"
echo "${CYAN}启动 Hermes 硬件进程监控...${NC}"
echo "${CYAN}----------------------------------------${NC}"

MONITOR_PORT=8900
if lsof -ti:$MONITOR_PORT > /dev/null 2>&1; then
    echo "${GREEN}✅ 硬件监控已在运行 (端口 $MONITOR_PORT)${NC}"
else
    nohup python3 "$REPO_DIR/hermes-monitor-server.py" > ~/.hermes/monitor.log 2>&1 &
    sleep 1
    if lsof -ti:$MONITOR_PORT > /dev/null 2>&1; then
        echo "${GREEN}✅ Hermes 硬件进程监控启动成功${NC}"
        echo "${CYAN}访问地址: http://localhost:$MONITOR_PORT${NC}"
    else
        echo "${YELLOW}⚠️ 硬件监控启动失败，查看日志: ~/.hermes/monitor.log${NC}"
    fi
fi

########################### 7. 启动 Hermes 端口诊断面板（Windows侧，独立于WSL网络） ###########################
echo -e "${CYAN}\n----------------------------------------${NC}"
echo "${CYAN}启动 Hermes 端口诊断面板（Windows侧）...${NC}"
echo "${CYAN}----------------------------------------${NC}"

DIAG_PORT=8921
# 用 Windows 的 curl.exe 检测（WSL 内 curl 访问不到 Windows 进程）
diag_ok() {
    curl.exe -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://127.0.0.1:$DIAG_PORT/health" 2>/dev/null | grep -qE "^[23]"
}
if diag_ok; then
    echo "${GREEN}✅ 端口诊断面板已在运行 (端口 $DIAG_PORT，Windows侧)${NC}"
else
    echo "启动 Windows 侧诊断面板..."
    _win_home="${WIN_USER_DIR#/mnt/c}"
    _win_home="C:${_win_home//\//\\}"
    cmd.exe /c "cd /d ${_win_home} && start_diag_win.bat" >/dev/null 2>&1
    sleep 2
    if diag_ok; then
        echo "${GREEN}✅ Hermes 端口诊断面板启动成功（Windows侧，WSL网络故障时仍可用）${NC}"
        echo "${CYAN}访问地址: http://localhost:$DIAG_PORT${NC}"
    else
        echo "${YELLOW}⚠️ 端口诊断面板启动失败，查看日志: ${_win_home}\\diag_win.log${NC}"
    fi
fi

########################### 8. 启动完成，回车退出 ###########################
echo -e "${CYAN}\n========================================${NC}"
echo "${GREEN}✅ Hermes-Agent 全部服务启动完成${NC}"
echo "${CYAN}========================================${NC}"
echo -n "${CYAN}按回车键退出...${NC}"
read </dev/tty

