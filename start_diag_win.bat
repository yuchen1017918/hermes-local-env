@echo off
chcp 65001 >nul
rem Hermes diag panel launcher (runs on Windows side, independent of WSL network)
set DIAG_PORT=8921
set BATLOG=C:\Users\77630\diag_launcher.log
echo [%date% %time%] launcher start >> "%BATLOG%"

netstat -ano 2>nul | findstr ":8921" | findstr "LISTENING" >nul
if %errorlevel%==0 (
    echo [%date% %time%] already running on 8921, skip >> "%BATLOG%"
    exit /b 0
)

rem wait for WSL filesystem (UNC path may be unavailable right after logon), up to 30s
set /a tries=0
:wait_wsl
if exist "\\wsl.localhost\Ubuntu-22.04\home\yuchen_wang\workspace\monitor\hermes-diag-server.py" goto wsl_ok
set /a tries+=1
if %tries% geq 15 (
    echo [%date% %time%] WSL not ready after 30s, exit >> "%BATLOG%"
    exit /b 1
)
timeout /t 2 /nobreak >nul
goto wait_wsl

:wsl_ok
echo [%date% %time%] WSL ready, launching panel >> "%BATLOG%"
wscript.exe "C:\Users\77630\start_diag_win.vbs"
echo [%date% %time%] launched >> "%BATLOG%"
echo [OK] diag started on 8921
