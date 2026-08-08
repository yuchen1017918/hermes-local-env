# renew_hwinfo.ps1 - HWiNFO 共享内存 12h 限制续期
# 每小时由计划任务运行：HWiNFO 运行超 10.5h 或未运行时，重启 HWiNFO（共享内存重新计时）
$ErrorActionPreference = 'SilentlyContinue'

$p = Get-Process HWiNFO64 -ErrorAction SilentlyContinue
if ($p) {
    $uptime = (Get-Date) - $p.StartTime
    if ($uptime.TotalHours -gt 10.5) {
        Stop-Process -Name HWiNFO64 -Force
        Start-Sleep 3
        Start-Process -FilePath 'C:\Users\77630\hwinfo\HWiNFO64.exe' -WorkingDirectory 'C:\Users\77630\hwinfo'
    }
} else {
    # HWiNFO 异常退出 → 重新拉起
    Start-Process -FilePath 'C:\Users\77630\hwinfo\HWiNFO64.exe' -WorkingDirectory 'C:\Users\77630\hwinfo'
}
