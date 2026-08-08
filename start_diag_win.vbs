' Hermes diag panel launcher - hidden window start (non-blocking)
' Called by start_diag_win.bat; inherits DIAG_PORT env var
' No hardcoded user/distro: reads env vars set by start_diag_win.bat
Set ws = CreateObject("Wscript.Shell")

' 1. pythonw.exe 路径：环境变量 PYTHONW 优先，否则自动探测
pyw = ws.ExpandEnvironmentStrings("%PYTHONW%")
If pyw = "%PYTHONW%" Or Len(Trim(pyw)) = 0 Then
    ' 探测常见 Python 安装位置
    pyw = ws.ExpandEnvironmentStrings("%USERPROFILE%\AppData\Local\Programs\Python\Python311\pythonw.exe")
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FileExists(pyw) Then
        pyw = ws.ExpandEnvironmentStrings("%USERPROFILE%\AppData\Local\Programs\Python\Python312\pythonw.exe")
    End If
    If Not fso.FileExists(pyw) Then
        pyw = "pythonw.exe"  ' 最后兜底：依赖 PATH
    End If
End If

' 2. 仓库 UNC 路径：环境变量 MONITOR_UNC（由 bat 探测注入）
monitorUnc = ws.ExpandEnvironmentStrings("%MONITOR_UNC%")
If monitorUnc = "%MONITOR_UNC%" Or Len(Trim(monitorUnc)) = 0 Then
    ' 兜底：WSL 默认发行版 + 当前用户（与 bat 探测逻辑一致）
    Set shell = CreateObject("Wscript.Shell")
    distro = ""
    On Error Resume Next
    distro = shell.Exec("wsl -l -q").StdOut.ReadAll
    On Error GoTo 0
    distro = Trim(Left(distro, InStr(distro, vbCrLf) - 1))
    If Len(distro) = 0 Then distro = "Ubuntu"
    user = shell.ExpandEnvironmentStrings("%USERNAME%")
    monitorUnc = "\\wsl.localhost\" & distro & "\home\" & user & "\workspace\monitor"
End If

' 3. 拼接命令并后台隐藏启动（0=隐藏窗口, False=不等待）
cmd = """" & pyw & """ """ & monitorUnc & "\hermes-diag-server.py"""
ws.Run cmd, 0, False
