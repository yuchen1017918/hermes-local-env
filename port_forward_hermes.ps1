# Hermes 端口转发脚本
# 将 WSL2 中的服务端口转发到 Windows，使手机可通过局域网访问
# 管理员权限运行: powershell -ExecutionPolicy Bypass -File "C:\Users\77630\port_forward_hermes.ps1"

$ports = @(8787, 9119, 8900, 8920)  # WebUI, Dashboard, 统一监控, 端口诊断

# 自动获取 WSL2 的 IP
$wslIP = (wsl -e hostname -I).Trim().Split()[0]
if (-not $wslIP) {
    Write-Host "❌ 无法获取 WSL2 IP，请确认 WSL 已启动" -ForegroundColor Red
    exit 1
}
Write-Host "WSL2 IP: $wslIP" -ForegroundColor Cyan

# 获取 Windows 局域网 IP
$winIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -match '^192\.168\.|^10\.|^172\.(1[6-9]|2\d|3[01])\.' -and
    $_.InterfaceAlias -notlike '*WSL*'
} | Select-Object -First 1).IPAddress

foreach ($port in $ports) {
    # 删除旧规则
    netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null

    # 添加新规则
    netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslIP
    Write-Host "✅ 端口转发: 0.0.0.0:$port → $wslIP`:$port" -ForegroundColor Green
}

# 防火墙放行
foreach ($port in $ports) {
    $fwRuleName = "Hermes-Port-Forward-${port}"
    # 先删旧规则（忽略不存在时的错误）
    netsh advfirewall firewall delete rule name="$fwRuleName" > $null 2>&1
    # 添加新规则
    netsh advfirewall firewall add rule name="$fwRuleName" dir=in action=allow protocol=TCP localport=$port > $null
    if ($?) { Write-Host "✅ 防火墙放行端口 $port" -ForegroundColor Green }
    else { Write-Host "⚠ 防火墙端口 $port 放行失败" -ForegroundColor Yellow }
}

Write-Host ""
if ($winIP) {
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  WebUI:      http://${winIP}:$($ports[0])" -ForegroundColor Green
    Write-Host "  Dashboard:  http://${winIP}:$($ports[1])" -ForegroundColor Green
    Write-Host "  统一监控:    http://${winIP}:$($ports[2])" -ForegroundColor Green
    Write-Host "  端口诊断:    http://${winIP}:$($ports[3])" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor White
} else {
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  WebUI:      http://localhost:$($ports[0])" -ForegroundColor Green
    Write-Host "  Dashboard:  http://localhost:$($ports[1])" -ForegroundColor Green
    Write-Host "  统一监控:    http://localhost:$($ports[2])" -ForegroundColor Green
    Write-Host "  端口诊断:    http://localhost:$($ports[3])" -ForegroundColor Green
    Write-Host "  (未检测到局域网IP，仅本机可用)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor White
}

Read-Host "按 Enter 退出"
