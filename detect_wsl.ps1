# ============================================================
# detect_wsl.ps1 — 探测 WSL 发行版与用户名（供 bat/脚本复用）
# ------------------------------------------------------------
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File detect_wsl.ps1
#   → 输出两行: <distro>\n<username>
#   powershell ... -File detect_wsl.ps1 -DistroOnly
#   → 只输出发行版
#   powershell ... -File detect_wsl.ps1 -UserOnly
#   → 只输出用户名
# ============================================================
param(
    [switch]$DistroOnly,
    [switch]$UserOnly
)

# wsl -l -q 输出 UTF-16LE，用 .NET 字节流解码规避管道乱码
function Get-WslDistroList {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wsl.exe'
    $psi.Arguments = '-l -q'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $raw = $ms.ToArray()
    if ($raw.Length -ge 2 -and $raw[0] -eq 0xFF -and $raw[1] -eq 0xFE) { $raw = $raw[2..($raw.Length-1)] }
    $text = [System.Text.Encoding]::Unicode.GetString($raw)
    return ($text -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
}

$distro = $env:WSL_DISTRO
if (-not $distro) {
    try { $distro = (Get-WslDistroList | Select-Object -First 1) } catch { $distro = $null }
}
if (-not $distro) {
    Write-Error "无法自动探测 WSL 发行版，请设置环境变量 WSL_DISTRO"
    exit 1
}

if ($DistroOnly) {
    Write-Output $distro
    exit 0
}

$user = $env:WSL_USER
if (-not $user) {
    try { $user = (wsl.exe -d $distro whoami 2>$null | Select-Object -First 1).Trim() } catch { $user = $null }
}
if (-not $user) {
    Write-Error "无法自动探测 WSL 用户名，请设置环境变量 WSL_USER"
    exit 1
}

if ($UserOnly) {
    Write-Output $user
    exit 0
}

Write-Output $distro
Write-Output $user
