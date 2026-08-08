# ============================================================
# install_tasks.ps1 — 一键创建 Hermes 本地环境任务计划
# ------------------------------------------------------------
# 用法（管理员 PowerShell）:
#   powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1
#   powershell -ExecutionPolicy Bypass -File .\install_tasks.ps1 -DryRun
#
# 功能:
#   1. 自动探测本机信息（Windows 用户 / 机器名 / WSL 发行版 / WSL 用户名）
#   2. 将 task-scheduler/*.xml 模板中的 {{占位符}} 替换为实际值
#   3. 以 UTF-16 编码生成临时 XML（schtasks 要求）
#   4. 通过 schtasks /Create /XML 导入每个任务
#
# 可用环境变量覆盖自动探测（跨机器部署时推荐显式指定）:
#   $env:WIN_USER / $env:WSL_DISTRO / $env:WSL_USER / $env:MONITOR_UNC
# ============================================================

param(
    [switch]$DryRun   # 只生成并显示任务定义，不实际导入
)

$ErrorActionPreference = 'Stop'
# 控制台 UTF-8 输出（中文显示不乱码）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
# 切换到本地目录（UNC 路径下 wsl.exe / cmd 无法正常启动）
Push-Location $env:TEMP
try {
$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # task-scheduler/ 上级 = 仓库根
$tplDir  = Join-Path $repoDir 'task-scheduler'

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Hermes 本地环境 — 任务计划安装" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ---------- 1. 自动探测本机信息 ----------
$winUser = $env:WIN_USER
if (-not $winUser) { $winUser = $env:USERNAME }
$computer = $env:COMPUTERNAME
$winProfile = Join-Path $env:USERPROFILE ''   # 如 C:\Users\<用户名>\

# WSL 发行版（取第一个）— 复用 detect_wsl.ps1（wsl -l -q 输出 UTF-16LE 需 .NET 解码）
$detectScript = Join-Path $repoDir 'detect_wsl.ps1'
$wslDistro = $env:WSL_DISTRO
if (-not $wslDistro) {
    try { $wslDistro = (powershell.exe -NoProfile -ExecutionPolicy Bypass -File $detectScript -DistroOnly 2>$null | Select-Object -First 1).Trim() } catch { $wslDistro = $null }
}
if (-not $wslDistro) { throw "无法自动探测 WSL 发行版，请设置环境变量 WSL_DISTRO" }

# WSL 用户名
$wslUser = $env:WSL_USER
if (-not $wslUser) {
    try { $wslUser = (powershell.exe -NoProfile -ExecutionPolicy Bypass -File $detectScript -UserOnly 2>$null | Select-Object -First 1).Trim() } catch { $wslUser = $null }
}
if (-not $wslUser) { throw "无法自动探测 WSL 用户名，请设置环境变量 WSL_USER" }

# WSL 家目录（默认为 /home/<user>）
$wslHome = "/home/$wslUser"

Write-Host "  本机信息:" -ForegroundColor Yellow
Write-Host "    Windows 用户 : $winUser"
Write-Host "    机器名       : $computer"
Write-Host "    Windows 目录 : $winProfile"
Write-Host "    WSL 发行版   : $wslDistro"
Write-Host "    WSL 用户名   : $wslUser"
Write-Host "    WSL 家目录   : $wslHome"

# ---------- 2. 占位符替换表 ----------
$map = @{
    '{{WIN_USER}}'    = $winUser
    '{{WIN_PROFILE}}' = $winProfile.TrimEnd('\')
    '{{COMPUTER}}'    = $computer
    '{{WSL_DISTRO}}'  = $wslDistro
    '{{WSL_USER}}'    = $wslUser
    '{{WSL_HOME}}'    = $wslHome
}

# ---------- 3. 部署配套脚本到用户目录 ----------
# 任务计划 HermesDiagPanel 在 %USERPROFILE% 运行 start_diag_win.bat，
# 其依赖 detect_wsl.ps1 / start_diag_win.vbs 必须在同目录，此处一并部署
$deployFiles = @('start_diag_win.bat', 'start_diag_win.vbs', 'detect_wsl.ps1')
if (-not $DryRun) {
    foreach ($df in $deployFiles) {
        $src = Join-Path $repoDir $df
        if (Test-Path $src) {
            Copy-Item $src $env:USERPROFILE -Force
            Write-Host "  📦 已部署 $df → $env:USERPROFILE" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  [DRY-RUN] 将部署: $($deployFiles -join ', ') → $env:USERPROFILE" -ForegroundColor DarkGray
}

# ---------- 4. 处理每个 XML 模板 ----------
$templates = Get-ChildItem -Path $tplDir -Filter '*.xml' | Sort-Object Name
$results = @()

foreach ($tpl in $templates) {
    $content = Get-Content -Path $tpl.FullName -Raw -Encoding UTF8

    # 替换占位符（含转义符，XML 中 & 需还原为 &amp; 已由模板保证）
    foreach ($k in $map.Keys) {
        $content = $content.Replace($k, $map[$k])
    }

    # 检查是否还有未替换的占位符
    $leftover = [regex]::Matches($content, '\{\{[^}]+\}\}') | ForEach-Object { $_.Value } | Select-Object -Unique
    if ($leftover) {
        Write-Host "  ⚠️  $($tpl.Name): 存在未替换占位符 $($leftover -join ', ')" -ForegroundColor Red
        continue
    }

    # 任务名 = URI 最后一段
    $taskName = ($tpl.BaseName -replace '_',' ')  # 文件名即任务名（含中文保持原名）

    if ($DryRun) {
        Write-Host "  [DRY-RUN] $($tpl.Name) → 任务 [$taskName]" -ForegroundColor DarkGray
        # 输出预览（前 3 行关键内容）
        $content -split "`n" | Where-Object { $_ -match 'Arguments|Command|Author' } | ForEach-Object {
            Write-Host "      $($_.Trim())" -ForegroundColor DarkGray
        }
        $results += "OK(DRY-RUN) $taskName"
        continue
    }

    # 写 UTF-16 LE 临时文件（schtasks /XML 需要）
    $tmp = Join-Path $env:TEMP "hermes_task_$($tpl.BaseName).xml"
    [System.IO.File]::WriteAllText($tmp, $content, [System.Text.Encoding]::Unicode)

    # 导入任务
    $out = schtasks /Create /TN $taskName /XML $tmp /F 2>&1
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ 已创建任务: $taskName" -ForegroundColor Green
        $results += "OK $taskName"
    } else {
        Write-Host "  ❌ 创建失败: $taskName" -ForegroundColor Red
        Write-Host "     $out" -ForegroundColor DarkRed
        $results += "FAIL $taskName : $out"
    }
}

# ---------- 4. 汇总 ----------
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " 完成。结果:" -ForegroundColor Cyan
$results | ForEach-Object { Write-Host "   $_" }
if (-not $DryRun) {
    Write-Host "  提示: 任务计划程序 → 任务计划程序库 可查看/编辑上述任务" -ForegroundColor DarkGray
}
} finally {
    Pop-Location
}
