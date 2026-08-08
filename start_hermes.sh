#!/bin/bash
# Hermes-Agent 一体化启动脚本（WebUI + Systemd托管网关）
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
        echo "⚠️ 警告：C盘挂载超时，跳过IP文件写入步骤"
        break
    fi
done

# 自动获取Windows用户名称、WSL本机IP
if [ -d /mnt/c/Users ]; then
    WIN_USER=$(ls /mnt/c/Users | grep -v Public | head -n1)
    WSL_IP=$(hostname -I | awk '{print $1}')
    echo "----------------------------------------"
    echo "当前WSL本机IP: $WSL_IP"
    echo "Windows登录用户目录: $WIN_USER"
    echo "----------------------------------------"

    # 将WSL IP写入Windows本地文件，供宿主机端口转发脚本读取
    IP_TARGET="/mnt/c/Users/${WIN_USER}/wsl_ip.txt"
    echo "$WSL_IP" > "$IP_TARGET"
    echo "✅ WSL IP已写入Windows文件: $IP_TARGET"
fi

########################### 3. 启动 Hermes WebUI 后台进程 ###########################
# 切换WebUI项目目录
cd ~/Hermes-Agent/hermes-webui || {
    echo "❌ WebUI目录不存在 ~/Hermes-Agent/hermes-webui，终止启动"
    exit 1
}

# 启动前清空历史日志，防止日志文件持续膨胀
> ~/hermes_webui.log
echo "正在后台启动 Hermes WebUI 服务..."
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
    echo "✅ Hermes WebUI 后台启动成功，进程持久运行"
    echo "WebUI日志路径: ~/hermes_webui.log"
else
    echo "❌ Hermes WebUI启动失败，请手动执行排查命令："
    echo "cd ~/Hermes-Agent/hermes-webui && python3 -u bootstrap.py --host 0.0.0.0 --no-browser"
    exit 2
fi

########################### 4. Tmux 独立会话启动 Hermes Gateway 网关 ###########################
echo -e "\n----------------------------------------"
echo "使用Tmux后台会话启动Hermes网关（无需systemd，规避启动失败）"
echo "----------------------------------------"

# 判断会话是否存在，不存在则新建后台会话
if ! tmux has-session -t hermes-gateway 2>/dev/null; then
    echo "创建Tmux后台会话 hermes-gateway"
    # 后台启动网关，日志写入独立文件
    tmux new-session -d -s hermes-gateway "hermes gateway run > ~/hermes_gateway.log 2>&1"
    sleep 2
else
    echo "Tmux会话 hermes-gateway 已存在，无需重复启动"
fi

# 校验网关进程是否运行
if pgrep -f "hermes gateway run" > /dev/null; then
    echo "✅ Hermes Gateway 网关启动成功，Tmux会话永久常驻"
    echo "网关日志文件：~/hermes_gateway.log"
    echo "实时查看网关日志命令：tail -f ~/hermes_gateway.log"
else
    echo "⚠️ Hermes Gateway 网关启动失败，请查看日志排查"
    echo "查看日志：tail -n 100 ~/hermes_gateway.log"
fi

echo -e "\n----------------------------------------"
echo "启动 Hermes Dashboard 仪表盘..."
echo "----------------------------------------"

DASHBOARD_PORT=9119
if lsof -ti:$DASHBOARD_PORT > /dev/null 2>&1; then
    echo "✅ Dashboard 已在运行 (端口 $DASHBOARD_PORT)"
else
    nohup hermes dashboard --host 0.0.0.0 --port $DASHBOARD_PORT > ~/.hermes/dashboard.log 2>&1 &
    sleep 2
    if lsof -ti:$DASHBOARD_PORT > /dev/null 2>&1; then
        echo "✅ Hermes Dashboard 启动成功"
        echo "访问地址: http://localhost:$DASHBOARD_PORT"
    else
        echo "⚠️ Dashboard 启动失败，查看日志: ~/.hermes/dashboard.log"
    fi
fi

########################### 6. 启动 Hermes 硬件进程监控 ###########################
echo -e "\n----------------------------------------"
echo "启动 Hermes 硬件进程监控..."
echo "----------------------------------------"

MONITOR_PORT=8900
if lsof -ti:$MONITOR_PORT > /dev/null 2>&1; then
    echo "✅ 硬件监控已在运行 (端口 $MONITOR_PORT)"
else
    nohup python3 ~/workspace/monitor/hermes-monitor-server.py > ~/.hermes/monitor.log 2>&1 &
    sleep 1
    if lsof -ti:$MONITOR_PORT > /dev/null 2>&1; then
        echo "✅ Hermes 硬件进程监控启动成功"
        echo "访问地址: http://localhost:$MONITOR_PORT"
    else
        echo "⚠️ 硬件监控启动失败，查看日志: ~/.hermes/monitor.log"
    fi
fi

########################### 7. 启动 Hermes 端口诊断面板 ###########################
echo -e "\n----------------------------------------"
echo "启动 Hermes 端口诊断面板..."
echo "----------------------------------------"

DIAG_PORT=8920
if lsof -ti:$DIAG_PORT > /dev/null 2>&1; then
    echo "✅ 端口诊断面板已在运行 (端口 $DIAG_PORT)"
else
    nohup python3 ~/workspace/monitor/hermes-diag-server.py > ~/.hermes/diag.log 2>&1 &
    sleep 1
    if lsof -ti:$DIAG_PORT > /dev/null 2>&1; then
        echo "✅ Hermes 端口诊断面板启动成功"
        echo "访问地址: http://localhost:$DIAG_PORT"
    else
        echo "⚠️ 端口诊断面板启动失败，查看日志: ~/.hermes/diag.log"
    fi
fi
