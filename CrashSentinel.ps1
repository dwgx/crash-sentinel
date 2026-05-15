# PC Crash Sentinel - Monitoring Engine
# Monitors CPU/GPU temperature, power, and load. Logs to CSV with instant disk flush.
# Crash-proof: every sample is written immediately so power loss won't corrupt data.
# https://github.com/dwgx/crash-sentinel

param(
    [string]$ConfigPath = "settings.json",
    [string]$LogDir = $null
)

# ============================================================
# LOAD CONFIG
# ============================================================
$config = @{
    monitor = @{
        interval_seconds = 5
        log_directory    = "."
        warn_temp_c      = 85
        critical_temp_c  = 90
        danger_temp_c    = 100
    }
}

if (Test-Path $ConfigPath) {
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.monitor) {
            if ($json.monitor.interval_seconds) { $config.monitor.interval_seconds = [int]$json.monitor.interval_seconds }
            if ($json.monitor.log_directory)   { $config.monitor.log_directory = $json.monitor.log_directory }
            if ($json.monitor.warn_temp_c)     { $config.monitor.warn_temp_c = [int]$json.monitor.warn_temp_c }
            if ($json.monitor.critical_temp_c) { $config.monitor.critical_temp_c = [int]$json.monitor.critical_temp_c }
            if ($json.monitor.danger_temp_c)   { $config.monitor.danger_temp_c = [int]$json.monitor.danger_temp_c }
        }
    } catch {}
}

if ($LogDir) { $config.monitor.log_directory = $LogDir }

$logDir = $config.monitor.log_directory
if (-not [System.IO.Path]::IsPathRooted($logDir)) {
    $logDir = Join-Path $PSScriptRoot $logDir
}
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$interval    = $config.monitor.interval_seconds
$WARN_TEMP   = $config.monitor.warn_temp_c
$CRIT_TEMP   = $config.monitor.critical_temp_c
$DANGER_TEMP = $config.monitor.danger_temp_c

# ============================================================
# INIT LOG FILE
# ============================================================
$logName = "CrashSentinel_" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".csv"
$logPath = Join-Path $logDir $logName
$header = "Time,CPU_Temp(C),CPU_Load(%),GPU_Temp(C),GPU_Power(W),GPU_Load(%),GPU_Clock(MHz)"
[System.IO.File]::AppendAllText($logPath, $header + "`n", [System.Text.Encoding]::UTF8)

# ============================================================
# STARTUP BANNER
# ============================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PC Crash Sentinel - Monitor Active" -ForegroundColor Cyan
Write-Host "  Interval : ${interval}s" -ForegroundColor Cyan
Write-Host "  Log      : $logName" -ForegroundColor Cyan
Write-Host "  Warn: ${WARN_TEMP}C  Crit: ${CRIT_TEMP}C  Danger: ${DANGER_TEMP}C" -ForegroundColor Cyan
Write-Host "  Close this window to stop monitoring" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# SENSOR FUNCTIONS
# ============================================================

function Get-GpuSensors {
    try {
        $line = nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,clocks.sm --format=csv,noheader,nounits 2>$null
        if (-not $line) { return @{ temp = -1; power = -1; load = -1; clock = -1 } }
        $parts = $line -split ',' | ForEach-Object { $_.Trim() }
        return @{
            temp  = [double]$parts[0]
            power = [double]$parts[1]
            load  = [int]$parts[2]
            clock = [int]$parts[3]
        }
    } catch {
        return @{ temp = -1; power = -1; load = -1; clock = -1 }
    }
}

function Get-CpuTemp {
    try {
        $tz = Get-Counter "\Thermal Zone Information(\_TZ.TZ00)\High Precision Temperature" -ErrorAction Stop
        $raw = $tz.CounterSamples[0].CookedValue
        if ($raw -gt 0) {
            return [math]::Round(($raw / 10.0) - 273.15, 1)
        }
    } catch {}
    return -1
}

function Get-CpuLoad {
    try {
        $cpu = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction Stop
        return [math]::Round($cpu.CounterSamples[0].CookedValue, 0)
    } catch {}
    return -1
}

# ============================================================
# MAIN LOOP
# ============================================================
$count = 0
$maxCpuTemp = 0
$maxGpuTemp = 0

while ($true) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $gpu = Get-GpuSensors
    $cpuTemp = Get-CpuTemp
    $cpuLoad = Get-CpuLoad

    if ($cpuTemp -gt $maxCpuTemp) { $maxCpuTemp = $cpuTemp }
    if ($gpu.temp -gt $maxGpuTemp) { $maxGpuTemp = $gpu.temp }

    # Write CSV with instant flush (crash-proof)
    $entry = "$time,$cpuTemp,$cpuLoad,$($gpu.temp),$($gpu.power),$($gpu.load),$($gpu.clock)"
    [System.IO.File]::AppendAllText($logPath, $entry + "`n", [System.Text.Encoding]::UTF8)

    # Console output
    $status = "[$time]  CPU: ${cpuTemp}C ${cpuLoad}%  |  GPU: $($gpu.temp)C $($gpu.load)% $($gpu.power)W  |  Peak CPU: ${maxCpuTemp}C GPU: ${maxGpuTemp}C"

    $danger = ($cpuTemp -ge $DANGER_TEMP) -or ($gpu.temp -ge $DANGER_TEMP)
    $crit   = ($cpuTemp -ge $CRIT_TEMP) -or ($gpu.temp -ge $CRIT_TEMP) -and (-not $danger)
    $warn   = ($cpuTemp -ge $WARN_TEMP) -or ($gpu.temp -ge $WARN_TEMP) -and (-not $crit) -and (-not $danger)

    if ($danger) {
        Write-Host "!!! DANGER !!! $status" -ForegroundColor Red
        [console]::Beep(1000, 500)
    } elseif ($crit) {
        Write-Host "CRITICAL: $status" -ForegroundColor Yellow
    } elseif ($warn) {
        Write-Host "WARN: $status" -ForegroundColor DarkYellow
    } else {
        Write-Host $status
    }

    $count++
    if ($count % 60 -eq 0) {
        $mins = $count * $interval / 60
        $kb   = [math]::Round((Get-Item $logPath).Length / 1KB, 1)
        Write-Host ("--- Running ${mins} min, log ${kb} KB ---") -ForegroundColor DarkGray
    }

    Start-Sleep -Seconds $interval
}
