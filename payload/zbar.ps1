# zbar - Process blocker
# Checks every 30 seconds, kills processes matching blocklist

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$blocklistFile = Join-Path $scriptDir "blocklist.txt"
$logFile = Join-Path $scriptDir "zbar-log.txt"
$pidFile = Join-Path $scriptDir "zbar.pid"
$killScreen = Join-Path $scriptDir "zbar-killscreen.ps1"
$ksTaskName = "zbar-killscreen"
$lastKillScreenTime = [datetime]::MinValue

# Write PID for diagnostics (ASCII so batch can read it)
[IO.File]::WriteAllText($pidFile, $PID.ToString())

while ($true) {
    # Reload blocklist each cycle so edits take effect without restart
    $blocklist = @(Get-Content $blocklistFile -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Trim().ToLower() } |
        Where-Object { $_ -and $_ -notmatch '^\s*#' })

    if ($blocklist.Count -gt 0) {
        foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
            if ($blocklist -contains $proc.ProcessName.ToLower()) {
                $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                try {
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    "$now  KILLED  $($proc.ProcessName)  (PID $($proc.Id))" |
                        Out-File $logFile -Append -Encoding utf8
                    # Launch killscreen on user desktop (max once per 60s)
                    # Must use scheduled task with InteractiveToken because zbar
                    # runs as SYSTEM in Session 0 where Start-Process is invisible
                    if ((Test-Path $killScreen) -and ((Get-Date) - $lastKillScreenTime).TotalSeconds -ge 60) {
                        $lastKillScreenTime = Get-Date
                        try {
                            Unregister-ScheduledTask -TaskName $ksTaskName -Confirm:$false -ErrorAction SilentlyContinue
                            $ksArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$killScreen`" -ProcessName `"$($proc.ProcessName)`""
                            $ksAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ksArgs
                            $ksUser = (Get-CimInstance Win32_ComputerSystem).UserName
                            if ($ksUser) {
                                $ksPrincipal = New-ScheduledTaskPrincipal -UserId $ksUser -LogonType Interactive -RunLevel Limited
                                Register-ScheduledTask -TaskName $ksTaskName -Action $ksAction -Principal $ksPrincipal -Force | Out-Null
                                Start-ScheduledTask -TaskName $ksTaskName
                            }
                        } catch {}
                    }
                } catch {
                    "$now  FAILED  $($proc.ProcessName)  (PID $($proc.Id))  $($_.Exception.Message)" |
                        Out-File $logFile -Append -Encoding utf8
                }
            }
        }
    }

    Start-Sleep -Seconds 30
}
