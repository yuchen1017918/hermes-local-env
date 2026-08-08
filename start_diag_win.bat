@echo off
chcp 65001 >nul
rem Hermes diag panel launcher (runs on Windows side, independent of WSL network)
set DIAG_PORT=8921
set BATLOG=%USERPROFILE%\diag_launcher.log
echo [%date% %time%] launcher start >> "%BATLOG%"

netstat -ano 2>nul | findstr ":8921" | findstr "LISTENING" >nul
if %errorlevel%==0 (
    echo [%date% %time%] already running on 8921, skip >> "%BATLOG%"
    exit /b 0
)

rem ---- 自动探测 WSL 发行版与用户名（无硬编码，可用环境变量覆盖） ----
rem wsl -l -q 输出为 UTF-16，bat 直接解析会乱码，故调用 detect_wsl.ps1 探测
if not defined WSL_DISTRO (
    for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0detect_wsl.ps1" -DistroOnly 2^>nul`) do set "WSL_DISTRO=%%i"
)
if not defined WSL_DISTRO (
    echo [%date% %time%] cannot detect WSL distro, exit >> "%BATLOG%"
    exit /b 1
)
if not defined WSL_USER (
    for /f "usebackq delims=" %%u in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0detect_wsl.ps1" -UserOnly 2^>nul`) do set "WSL_USER=%%u"
)
if not defined WSL_USER (
    echo [%date% %time%] cannot detect WSL user, exit >> "%BATLOG%"
    exit /b 1
)

rem ---- 仓库路径：默认 \\wsl.localhost\<distro>\home\<user>\workspace\monitor，可用 MONITOR_UNC 覆盖 ----
if not defined MONITOR_UNC set "MONITOR_UNC=\\wsl.localhost\%WSL_DISTRO%\home\%WSL_USER%\workspace\monitor"

rem wait for WSL filesystem (UNC path may be unavailable right after logon), up to 30s
set /a tries=0
:wait_wsl
if exist "%MONITOR_UNC%\hermes-diag-server.py" goto wsl_ok
set /a tries+=1
if %tries% geq 15 (
    echo [%date% %time%] WSL not ready after 30s, exit >> "%BATLOG%"
    exit /b 1
)
timeout /t 2 /nobreak >nul
goto wait_wsl

:wsl_ok
echo [%date% %time%] WSL ready, launching panel >> "%BATLOG%"
set "MONITOR_UNC=%MONITOR_UNC%"
rem vbs 需本地副本（wscript 默认禁止从 UNC 直接运行脚本）
if not exist "%USERPROFILE%\start_diag_win.vbs" (
    copy /y "%MONITOR_UNC%\start_diag_win.vbs" "%USERPROFILE%\start_diag_win.vbs" >nul 2>&1
)
wscript.exe "%USERPROFILE%\start_diag_win.vbs"
echo [%date% %time%] launched >> "%BATLOG%"
echo [OK] diag started on 8921
