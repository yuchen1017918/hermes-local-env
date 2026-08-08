# LHM 温度读取诊断脚本
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
Write-Output "HERE: $here"
try {
    Add-Type -Path (Join-Path $here 'LibreHardwareMonitorLib.dll') -ErrorAction Stop
    Write-Output "Add-Type OK"
} catch {
    Write-Output "Add-Type FAIL: $($_.Exception.Message)"
    exit 1
}
try {
    $comp = New-Object LibreHardwareMonitor.Hardware.Computer
    $comp.IsCpuEnabled = $true
    $comp.IsGpuEnabled = $true
    $comp.Open()
    $comp.AcceptNewConfigurations()
    Start-Sleep -Milliseconds 1200
    Write-Output ("Hardware count: {0}" -f $comp.Hardware.Count)
    foreach ($hw in $comp.Hardware) {
        $hw.Update()
        foreach ($s in $hw.Sensors) {
            if ($s.SensorType.ToString() -eq 'Temperature') {
                Write-Output ("TEMP|{0}|{1}|{2}|{3}" -f $hw.HardwareType, $hw.Name, $s.Name, $s.Value)
            }
        }
    }
    $comp.Close()
} catch {
    Write-Output "READ FAIL: $($_.Exception.Message)"
}
