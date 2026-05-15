# PC Crash Sentinel

**[English](#english) | [中文](#chinese)**

---

## English

### What is this?

A lightweight, zero-dependency Windows tool that monitors your CPU and GPU in real time and automatically diagnoses why your PC crashed. If your computer suddenly powers off during gaming, rendering, or heavy workloads — this finds the root cause.

### Features

- **Real-time monitoring** — CPU temp, CPU load, GPU temp, GPU power, GPU load, GPU clock
- **Crash-proof logging** — Every sample is flushed to disk immediately; power loss won't corrupt data
- **Automatic crash diagnosis** — After an unexpected shutdown, generates a report telling you if it was thermal, power, or something else
- **Dual report format** — Plain text (.txt) for quick reading, HTML for visual analysis
- **Zero dependencies** — Uses only Windows built-in performance counters and `nvidia-smi` (comes with NVIDIA drivers)
- **Configurable** — Edit `settings.json` to change thresholds, interval, log paths
- **Optional auto-start** — Install as a scheduled task to monitor every session

### Requirements

- Windows 10 or 11
- NVIDIA GPU with drivers installed
- PowerShell 5.1 (built into Windows)

### Quick Start

1. **Download** the latest release zip and extract it
2. **Double-click `run.bat`** to start monitoring
3. Do whatever caused your PC to crash before (gaming, rendering, etc.)
4. After a crash and reboot, run `CrashReport.ps1` to see what happened:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File CrashReport.ps1
   ```

### Installation (Optional)

Run `setup.bat` as Administrator to install two scheduled tasks:
- **CrashSentinel_Monitor** — starts monitoring automatically when you log in
- **CrashSentinel_Report** — runs on system boot, generates a report if a crash was detected

To uninstall, use Windows Task Scheduler to delete both tasks.

### How It Works

```
CrashSentinel.ps1 (runs in background)
  |
  +--> Every 5 seconds:
  |      - Reads GPU sensors via nvidia-smi
  |      - Reads CPU temp via ACPI Thermal Zone
  |      - Reads CPU load via Windows perf counters
  |      - Writes to timestamped CSV file
  |
  +--> Console shows real-time temps with color warnings:
         Green = normal, Yellow = hot, Red = danger + beep

After unexpected shutdown:
  
CrashReport.ps1
  |
  +--> Checks Windows Event Log for Event ID 41 (Kernel-Power)
  +--> Finds the latest monitoring log
  +--> Analyzes the last minutes before crash
  +--> Generates diagnosis + recommendations
  +--> Outputs .txt and .html reports
```

### Sample Crash Report

```
========================================
  PC Crash Sentinel - Crash Report
  Crash detected at: 2026-05-10 06:15:07
========================================

SESSION SUMMARY:
  Duration        : 2h 8m
  GPU Temp Max    : 86C
  GPU Power Max   : 160W

LAST 12 SAMPLES BEFORE CRASH:
  Time      CPU/T  CPU%  GPU/T  GPU%   GPU/W
  06:14:42  27.9   5     81     69     109
  06:14:48  27.9   8     82     68     101
  06:14:54  27.9   4     83     71     110
  06:15:00  27.9   6     79     65      87
  06:15:06  27.9   7     73     49      86
  06:15:07  --- SYSTEM POWER LOSS ---

DIAGNOSIS:
  THERMAL THROTTLE CRASH: GPU hit critical temp (86C).
  Sustained near-max temps caused VRM/power delivery to overload.

RECOMMENDATIONS:
  - Cap frame rate to reduce sustained GPU load
  - Limit GPU power target to 80-85%
  - Improve laptop ventilation
```

### Configuration

Edit `settings.json`:

```json
{
    "monitor": {
        "interval_seconds": 5,
        "log_directory": ".",
        "warn_temp_c": 85,
        "critical_temp_c": 90,
        "danger_temp_c": 100
    },
    "report": {
        "format": "both",
        "output_directory": "./reports",
        "keep_logs_days": 30
    },
    "startup": {
        "auto_start_monitor": false,
        "auto_start_report": true
    }
}
```

### FAQ

**Q: Why is CPU temperature always the same value?**
A: The ACPI thermal zone sensor reads motherboard/package temperature, not individual core temps. On some laptops, this sensor reports a different value than the CPU die temp. GPU temperature and power draw are the primary indicators for crash diagnosis.

**Q: Does this work with AMD or Intel GPUs?**
A: Currently NVIDIA only (via `nvidia-smi`). AMD support can be added — contributions welcome.

**Q: Will this slow down my games?**
A: No. The script polls every 5 seconds and reads existing OS counters. CPU usage is negligible.

**Q: What if I get "PowerShell execution policy" errors?**
A: Run this command first: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

---

## 中文

### 这是什么？

一个轻量、零依赖的 Windows 工具，实时监控 CPU 和 GPU，并在电脑崩溃后自动诊断原因。如果你的电脑在玩游戏、渲染或高负载时突然断电——这个工具帮你找到根因。

### 功能

- **实时监控** — CPU 温度、CPU 负载、GPU 温度、GPU 功耗、GPU 负载、GPU 频率
- **断电不丢数据** — 每条记录即时刷入磁盘，突然断电也不会损坏日志
- **自动崩溃诊断** — 意外关机重启后，生成诊断报告，告诉你是温度还是供电问题
- **双格式报告** — 纯文本 (.txt) 快速阅读，HTML 可视化分析
- **零依赖** — 仅使用 Windows 自带性能计数器和 nvidia-smi（NVIDIA 驱动自带）
- **可配置** — 编辑 `settings.json` 修改阈值、间隔、日志路径
- **可选开机自启** — 安装为计划任务，每次登录自动开始监控

### 系统要求

- Windows 10 或 11
- NVIDIA 显卡及驱动
- PowerShell 5.1（Windows 自带）

### 快速开始

1. **下载**最新 Release zip 并解压
2. **双击 `run.bat`** 启动监控
3. 正常玩游戏/做之前会崩溃的事
4. 崩溃重启后，运行报告脚本：
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File CrashReport.ps1
   ```

### 安装（可选）

以管理员身份运行 `setup.bat`，会安装两个计划任务：
- **CrashSentinel_Monitor** — 登录时自动启动监控
- **CrashSentinel_Report** — 系统启动时检测是否有崩溃，自动生成报告

卸载：在 Windows 任务计划程序中删除这两个任务即可。

### 配置

编辑 `settings.json`（上面有说明），支持中英文。

### 常见问题

**Q: 为什么 CPU 温度一直不变？**
A: ACPI 热区传感器读取的是主板/封装温度，不是单个核心温度。部分笔记本上这个数值偏低。GPU 温度和功耗是崩溃诊断的主要指标。

**Q: 支持 AMD 或 Intel 显卡吗？**
A: 目前仅 NVIDIA（通过 nvidia-smi）。欢迎提交 PR 添加 AMD 支持。

**Q: 会影响游戏性能吗？**
A: 不会。脚本每 5 秒轮询一次，读取的是系统已有的计数器，CPU 占用几乎为零。

**Q: 提示"PowerShell 执行策略"错误？**
A: 先运行：`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

---

## License

MIT — see [LICENSE](LICENSE)

## Contributing

Issues and pull requests are welcome. For major changes, please open an issue first to discuss what you'd like to change.
