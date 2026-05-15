# PC Crash Sentinel - Diagnostic Report Generator
# Detects unexpected shutdowns and generates crash analysis reports.
# https://github.com/dwgx/crash-sentinel

param(
    [string]$ConfigPath = "settings.json",
    [switch]$Force           # Generate report even if no recent crash detected
)

# ============================================================
# LOAD CONFIG
# ============================================================
$config = @{
    report = @{
        format          = "both"
        output_directory = "./reports"
        keep_logs_days  = 30
    }
    monitor = @{
        critical_temp_c = 90
        danger_temp_c   = 100
    }
}

if (Test-Path $ConfigPath) {
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.report) {
            if ($json.report.format)           { $config.report.format = $json.report.format }
            if ($json.report.output_directory) { $config.report.output_directory = $json.report.output_directory }
            if ($json.report.keep_logs_days)   { $config.report.keep_logs_days = [int]$json.report.keep_logs_days }
        }
        if ($json.monitor) {
            if ($json.monitor.critical_temp_c) { $config.monitor.critical_temp_c = [int]$json.monitor.critical_temp_c }
            if ($json.monitor.danger_temp_c)   { $config.monitor.danger_temp_c = [int]$json.monitor.danger_temp_c }
        }
    } catch {}
}

$reportDir = $config.report.output_directory
if (-not [System.IO.Path]::IsPathRooted($reportDir)) {
    $reportDir = Join-Path $PSScriptRoot $reportDir
}
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }

$CRIT_TEMP   = $config.monitor.critical_temp_c
$DANGER_TEMP = $config.monitor.danger_temp_c

# ============================================================
# DETECT CRASH
# ============================================================
$crashTime = $null
if (-not $Force) {
    try {
        $recentCrash = Get-WinEvent -LogName System -MaxEvents 50 |
            Where-Object { $_.Id -eq 41 -and $_.TimeCreated -gt (Get-Date).AddMinutes(-10) } |
            Select-Object -First 1
        if ($recentCrash) {
            $crashTime = $recentCrash.TimeCreated
        }
    } catch {}
}

if (-not $crashTime -and -not $Force) {
    # No recent crash, nothing to do
    exit 0
}

# ============================================================
# FIND LOG FILE
# ============================================================
$logFiles = Get-ChildItem (Join-Path $PSScriptRoot "CrashSentinel_*.csv") |
    Sort-Object LastWriteTime -Descending

if (-not $logFiles -or $logFiles.Count -eq 0) {
    Write-Host "No CrashSentinel log files found." -ForegroundColor Red
    exit 1
}

$logFile = $logFiles[0].FullName
$data = Import-Csv $logFile

if ($data.Count -lt 2) {
    Write-Host "Log file too short for analysis." -ForegroundColor Red
    exit 1
}

# ============================================================
# ANALYZE LOG
# ============================================================
$firstTime  = [datetime]::Parse($data[0].Time)
$lastTime   = [datetime]::Parse($data[-1].Time)
$duration   = $lastTime - $firstTime

$cols = $data[0].PSObject.Properties.Name
$maxCpuTemp  = if ('CPU_Temp(C)' -in $cols) { ($data | Measure-Object -Property 'CPU_Temp(C)' -Maximum).Maximum } else { -1 }
$maxGpuTemp  = if ('GPU_Temp(C)' -in $cols) { ($data | Measure-Object -Property 'GPU_Temp(C)' -Maximum).Maximum } else { -1 }
$maxGpuPower = if ('GPU_Power(W)' -in $cols) { ($data | Measure-Object -Property 'GPU_Power(W)' -Maximum).Maximum } else { -1 }
$maxGpuLoad  = if ('GPU_Load(%)' -in $cols) { ($data | Measure-Object -Property 'GPU_Load(%)' -Maximum).Maximum } else { -1 }
$maxCpuLoad  = if ('CPU_Load(%)' -in $cols) { ($data | Measure-Object -Property 'CPU_Load(%)' -Maximum).Maximum } else { -1 }

# Average temps in last 2 minutes
$recentCutoff = $lastTime.AddMinutes(-2)
$recentData = $data | Where-Object { [datetime]::Parse($_.Time) -gt $recentCutoff }
if ($recentData.Count -eq 0) { $recentData = $data[-10..-1] }

$avgRecentGpu = if ('GPU_Temp(C)' -in $cols) { [math]::Round(($recentData | Measure-Object -Property 'GPU_Temp(C)' -Average).Average, 1) } else { -1 }
$avgRecentPower = if ('GPU_Power(W)' -in $cols) { [math]::Round(($recentData | Measure-Object -Property 'GPU_Power(W)' -Average).Average, 1) } else { -1 }

# Check for power fluctuation (surge-dip pattern)
$powerValues = $recentData | ForEach-Object { [double]$_.'GPU_Power(W)' }
$powerVolatility = 0
if ($powerValues.Count -gt 1) {
    $maxPow = ($powerValues | Measure-Object -Maximum).Maximum
    $minPow = ($powerValues | Measure-Object -Minimum).Minimum
    $powerVolatility = [math]::Round($maxPow - $minPow, 0)
}

# ============================================================
# DIAGNOSIS
# ============================================================
$diagnosis = ""
$recommendations = @()

if ($maxGpuTemp -ge $DANGER_TEMP) {
    $diagnosis = "THERMAL SHUTDOWN: GPU reached dangerous temperature (${maxGpuTemp}C >= ${DANGER_TEMP}C threshold). The system cut power to protect hardware."
    $recommendations += "Clean fans and heatsinks immediately"
    $recommendations += "Replace thermal paste (GPU + CPU)"
    $recommendations += "Limit GPU power target to 80% in NVIDIA Control Panel"
    $recommendations += "Check that cooling pad fans are working"
} elseif ($maxGpuTemp -ge $CRIT_TEMP) {
    $diagnosis = "THERMAL THROTTLE CRASH: GPU hit critical temperature (${maxGpuTemp}C). Sustained near-max temps caused VRM/power delivery to overload."
    $recommendations += "Cap frame rate to reduce sustained GPU load"
    $recommendations += "Limit GPU power target to 80-85%"
    $recommendations += "Improve laptop ventilation (raise rear, clean vents)"
    $recommendations += "Consider replacing thermal paste"
} elseif ($powerVolatility -ge 60) {
    $diagnosis = "POWER DELIVERY FAILURE: GPU power draw fluctuated wildly ($powerVolatility W swing) in the final minutes. The VRM or power adapter overload protection likely triggered."
    $recommendations += "Check power adapter: ensure it is the original high-wattage adapter"
    $recommendations += "Limit GPU power target in NVIDIA Control Panel"
    $recommendations += "Test with a different power outlet"
    $recommendations += "If on a power strip, plug directly into wall"
} elseif ($maxGpuTemp -ge 80) {
    $diagnosis = "SUSPECTED THERMAL BUILDUP: GPU reached ${maxGpuTemp}C. While below critical threshold, sustained heat may have triggered protection circuits."
    $recommendations += "Monitor temperatures with CrashSentinel during next session"
    $recommendations += "Clean laptop fans and ensure good airflow"
    $recommendations += "Consider capping frame rate to reduce heat generation"
} else {
    $diagnosis = "UNKNOWN: The crash occurred without clear thermal or power warning signs. Possible causes: driver crash, software conflict, or external power interruption."
    $recommendations += "Check Windows Event Viewer for additional clues"
    $recommendations += "Update GPU drivers to latest version"
    $recommendations += "Run memory diagnostic (mdsched.exe)"
    $recommendations += "Check power outlet and adapter connections"
}

# ============================================================
# GENERATE REPORT
# ============================================================
$reportTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportBase = Join-Path $reportDir "CrashReport_$reportTime"

# --- TXT Report ---
if ($config.report.format -eq "txt" -or $config.report.format -eq "both") {
    $txt = @()
    $txt += "========================================"
    $txt += "  PC Crash Sentinel - Crash Report"
    if ($crashTime) { $txt += "  Crash detected at: $($crashTime.ToString('yyyy-MM-dd HH:mm:ss'))" }
    $txt += "  Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $txt += "========================================"
    $txt += ""
    $txt += "SESSION SUMMARY:"
    $txt += "  Log file        : $(Split-Path $logFile -Leaf)"
    $txt += "  Start time      : $($firstTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $txt += "  End time        : $($lastTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $durStr = "$([int]$duration.TotalHours)h $($duration.Minutes)m"
    $txt += "  Duration        : $durStr"
    $txt += "  Total samples   : $($data.Count)"
    $txt += ""
    $txt += "PEAK VALUES:"
    $txt += "  CPU Temp Max    : ${maxCpuTemp}C"
    $txt += "  CPU Load Max    : ${maxCpuLoad}%"
    $txt += "  GPU Temp Max    : ${maxGpuTemp}C"
    $txt += "  GPU Power Max   : ${maxGpuPower}W"
    $txt += "  GPU Load Max    : ${maxGpuLoad}%"
    $txt += ""
    $txt += "FINAL 2 MINUTES (avg):"
    $txt += "  GPU Temp avg    : ${avgRecentGpu}C"
    $txt += "  GPU Power avg   : ${avgRecentPower}W"
    $txt += "  Power fluctuation: ${powerVolatility}W"
    $txt += ""
    $txt += "LAST 12 SAMPLES BEFORE CRASH:"
    $lastSamples = $data[-12..-1]
    $txt += "  Time       CPU/T  CPU%  GPU/T  GPU%  GPU/W  GPU/MHz"
    foreach ($s in $lastSamples) {
        $t = ([datetime]::Parse($s.Time)).ToString("HH:mm:ss")
        $txt += ("  $t  $($s.'CPU_Temp(C)')     $($s.'CPU_Load(%)')     $($s.'GPU_Temp(C)')     $($s.'GPU_Load(%)')     $($s.'GPU_Power(W)')     $($s.'GPU_Clock(MHz)')")
    }
    $txt += ""
    $txt += "========================================"
    $txt += "DIAGNOSIS:"
    $txt += "  $diagnosis"
    $txt += ""
    $txt += "RECOMMENDATIONS:"
    foreach ($r in $recommendations) { $txt += "  - $r" }
    $txt += "========================================"

    $txtPath = "$reportBase.txt"
    $txt | Out-File $txtPath -Encoding UTF8
    Write-Host "Text report saved: $txtPath" -ForegroundColor Green
}

# --- HTML Report ---
if ($config.report.format -eq "html" -or $config.report.format -eq "both") {
    $rows = ""
    $lastSamples = $data[-12..-1]
    foreach ($s in $lastSamples) {
        $t = ([datetime]::Parse($s.Time)).ToString("HH:mm:ss")
        $gt = $s.'GPU_Temp(C)'
        $color = if ([double]$gt -ge $DANGER_TEMP) { "danger" } elseif ([double]$gt -ge $CRIT_TEMP) { "warn" } else { "" }
        $rows += "<tr class='$color'><td>$t</td><td>$($s.'CPU_Temp(C)')</td><td>$($s.'CPU_Load(%)')</td><td>$gt</td><td>$($s.'GPU_Load(%)')</td><td>$($s.'GPU_Power(W)')</td><td>$($s.'GPU_Clock(MHz)')</td></tr>`n"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Crash Sentinel - Crash Report</title>
<style>
body { font-family: 'Segoe UI', Arial, sans-serif; background:#111; color:#ddd; margin:0; padding:40px; }
.container { max-width:900px; margin:0 auto; background:#1a1a1a; border-radius:10px; padding:30px; box-shadow:0 0 20px rgba(255,0,0,0.15); }
h1 { color:#ff4444; margin:0 0 5px 0; }
h2 { color:#ff8800; margin-top:30px; }
.summary { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin:15px 0; }
.summary-item { background:#222; padding:12px; border-radius:6px; }
.summary-item .label { color:#888; font-size:12px; text-transform:uppercase; }
.summary-item .value { font-size:20px; font-weight:bold; }
table { width:100%; border-collapse:collapse; margin:10px 0; }
th { background:#333; padding:10px; text-align:left; font-size:13px; color:#aaa; }
td { padding:8px 10px; border-bottom:1px solid #2a2a2a; font-family:monospace; font-size:13px; }
tr.warn td { background:rgba(255,136,0,0.1); }
tr.danger td { background:rgba(255,0,0,0.15); color:#ff6666; }
.diagnosis { background:#1a0000; border-left:4px solid #ff4444; padding:15px 20px; margin:20px 0; border-radius:0 8px 8px 0; }
.diagnosis .label { color:#ff4444; font-weight:bold; }
.recommendations { list-style:none; padding:0; }
.recommendations li { padding:8px 15px; margin:5px 0; background:#222; border-radius:6px; }
.recommendations li::before { content:'> '; color:#ff8800; }
.footer { text-align:center; color:#555; margin-top:30px; font-size:12px; }
a { color:#ff8800; }
</style>
</head>
<body>
<div class="container">
<h1>PC Crash Sentinel - Crash Report</h1>
"@
    if ($crashTime) {
        $html += "<p>Crash detected at: $($crashTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>`n"
    }
    $html += "<p>Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>`n"
    $html += "<p>Log file: $(Split-Path $logFile -Leaf)</p>`n"

    $durStr = "$([int]$duration.TotalHours)h $($duration.Minutes)m"
    $html += @"
<h2>Session Summary</h2>
<div class="summary">
<div class="summary-item"><div class="label">Duration</div><div class="value">$durStr</div></div>
<div class="summary-item"><div class="label">Samples</div><div class="value">$($data.Count)</div></div>
<div class="summary-item"><div class="label">GPU Max Temp</div><div class="value">${maxGpuTemp}C</div></div>
<div class="summary-item"><div class="label">GPU Max Power</div><div class="value">${maxGpuPower}W</div></div>
<div class="summary-item"><div class="label">CPU Max Temp</div><div class="value">${maxCpuTemp}C</div></div>
<div class="summary-item"><div class="label">CPU Max Load</div><div class="value">${maxCpuLoad}%</div></div>
</div>

<h2>Last 60 Seconds Before Crash</h2>
<table>
<tr><th>Time</th><th>CPU(C)</th><th>CPU%</th><th>GPU(C)</th><th>GPU%</th><th>GPU(W)</th><th>GPU(MHz)</th></tr>
$rows
</table>

<div class="diagnosis">
<div class="label">DIAGNOSIS</div>
<p>$diagnosis</p>
</div>

<h2>Recommendations</h2>
<ul class="recommendations">
"@
    foreach ($r in $recommendations) {
        $html += "<li>$r</li>`n"
    }
    $html += @"
</ul>

<div class="footer">
PC Crash Sentinel - <a href="https://github.com/dwgx/crash-sentinel">github.com/user/crash-sentinel</a>
</div>
</div>
</body>
</html>
"@

    $htmlPath = "$reportBase.html"
    $html | Out-File $htmlPath -Encoding UTF8
    Write-Host "HTML report saved: $htmlPath" -ForegroundColor Green
}

# ============================================================
# CLEANUP OLD LOGS
# ============================================================
try {
    $keepDays = $config.report.keep_logs_days
    $cutoff = (Get-Date).AddDays(-$keepDays)
    Get-ChildItem (Join-Path $PSScriptRoot "CrashSentinel_*.csv") |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
} catch {}

Write-Host "`nDiagnosis: $diagnosis" -ForegroundColor Cyan
