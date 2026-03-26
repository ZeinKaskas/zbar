# zbar — Complete Technical Documentation

## Table of Contents

1. [What is zbar?](#what-is-zbar)
2. [Why it exists](#why-it-exists)
3. [How it works — The Big Picture](#how-it-works--the-big-picture)
4. [Architecture](#architecture)
5. [File-by-File Breakdown](#file-by-file-breakdown)
6. [The Blocklist](#the-blocklist)
7. [Installation Deep Dive](#installation-deep-dive)
8. [Persistence Mechanism](#persistence-mechanism)
9. [The Kill Loop](#the-kill-loop)
10. [The Diagnostic System](#the-diagnostic-system)
11. [Uninstallation](#uninstallation)
12. [Windows Defender Exclusion](#windows-defender-exclusion)
13. [Common Modifications](#common-modifications)
14. [Troubleshooting Guide](#troubleshooting-guide)
15. [Design Decisions and History](#design-decisions-and-history)
16. [Security Considerations](#security-considerations)
17. [Technical Reference](#technical-reference)

---

## What is zbar?

zbar is a lightweight Windows process blocker that runs silently in the background and kills gaming-related processes every 5 minutes. It's designed as a parental control tool — you install it on a PC you own, and it prevents gaming applications from running.

**Key characteristics:**
- USB-deployable: everything lives on a USB stick, no internet needed
- One-click install: double-click `Install.bat`, done
- Survives reboots: registered as a Windows Scheduled Task
- Auto-restarts: if the process dies, Task Scheduler restarts it within 1 minute (up to 999 times)
- No visible window: runs as a hidden PowerShell process
- Editable blocklist: add or remove games by editing a text file, changes take effect within 5 minutes
- Comprehensive diagnostics: `Check.bat` produces a full system report
- Clean uninstall: `Uninstall.bat` removes everything

**What it is NOT:**
- It is not malware. It does not collect data, phone home, or modify system files.
- It is not adversarial. If someone finds it and deletes it, it's gone. It doesn't try to survive active removal.
- It does not block network traffic, edit hosts files, modify DNS, or touch game files.
- It only kills processes. That's it.

---

## Why it exists

This was built as a DIY parental control tool for a specific use case: lending a Windows PC to a minor family member (referred to as "Stri" in development) and preventing them from playing video games on it. Commercial parental control solutions exist (Windows Family Safety, Qustodio, Net Nanny, etc.), but a custom solution was preferred for simplicity and full control.

---

## How it works — The Big Picture

```
USB STICK                          TARGET PC
┌─────────────────┐               ┌──────────────────────────────────┐
│ Install.bat     │──── run ────► │ C:\ProgramData\zbar\             │
│ Uninstall.bat   │               │   zbar.ps1        (blocker)      │
│ Check.bat       │               │   blocklist.txt   (game list)    │
│ payload/        │               │   zbar-check.ps1  (diagnostics)  │
│   zbar.ps1      │               │   zbar.pid        (process ID)   │
│   blocklist.txt │               │   zbar-log.txt    (kill log)     │
│   zbar-install  │               │                                  │
│   zbar-check    │               │ Task Scheduler                   │
│   zbar-uninstall│               │   "zbar" task (boot + logon)     │
└─────────────────┘               │                                  │
                                  │ Windows Defender                 │
                                  │   Exclusion for install dir      │
                                  └──────────────────────────────────┘
```

**The flow:**

1. User plugs in USB, double-clicks `Install.bat`
2. `Install.bat` (3 lines) calls `zbar-install.ps1` with the USB path
3. `zbar-install.ps1` requests admin elevation (UAC prompt)
4. Once elevated, it:
   - Copies `zbar.ps1`, `blocklist.txt`, and `zbar-check.ps1` to `C:\ProgramData\zbar\`
   - Adds a Windows Defender exclusion for that directory
   - Creates a Scheduled Task named "zbar" that triggers at boot and at logon
   - Starts the task immediately
   - Verifies everything worked
   - Writes an install report to the USB
5. `zbar.ps1` runs in an infinite loop:
   - Read blocklist from file
   - Get all running processes
   - If any process name matches the blocklist, force-kill it
   - Log the kill
   - Sleep 5 minutes
   - Repeat

---

## Architecture

### Directory Structure

```
zbar/                              ← Root folder (lives on USB or anywhere)
├── Install.bat                    ← 3-line wrapper, calls zbar-install.ps1
├── Uninstall.bat                  ← 3-line wrapper, calls zbar-uninstall.ps1
├── Check.bat                      ← 3-line wrapper, calls zbar-check.ps1
├── README.md                      ← Quick-start instructions
├── DOCUMENTATION.md               ← This file
└── payload/                       ← All scripts that do the actual work
    ├── zbar.ps1                   ← The blocker (runs on target PC forever)
    ├── blocklist.txt              ← Process names to kill (one per line)
    ├── zbar-install.ps1           ← Full installer with elevation + fallbacks
    ├── zbar-uninstall.ps1         ← Full uninstaller with elevation
    └── zbar-check.ps1             ← Comprehensive diagnostic tool (858 lines)
```

### Installed File Structure (on target PC)

```
C:\ProgramData\zbar\
├── zbar.ps1                       ← The blocker script (copied from USB)
├── blocklist.txt                  ← The game list (copied from USB)
├── zbar-check.ps1                 ← Diagnostics (copied from USB)
├── zbar.pid                       ← Contains the PID of the running blocker
└── zbar-log.txt                   ← Kill log (created at first kill)
```

### Why `C:\ProgramData\zbar\`?

- `C:\ProgramData` is a standard Windows directory for application data shared across all users
- Regular users can create files here (BUILTIN\Users have Write permission by default)
- It's not in any user's profile, so it persists regardless of which user logs in
- It's not a highly visible location (most users never browse ProgramData)

---

## File-by-File Breakdown

### `Install.bat`

```batch
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0payload\zbar-install.ps1" -UsbDir "%~dp0"
pause
```

That's the entire file. Three lines.

- `@echo off` — suppress command echoing
- `powershell -ExecutionPolicy Bypass` — run PowerShell, bypassing any script execution restrictions
- `-File "%~dp0payload\zbar-install.ps1"` — run the install script from the USB's payload folder
- `-UsbDir "%~dp0"` — pass the USB drive path to the script so it knows where to write reports
- `%~dp0` — batch variable that expands to the drive and path of the batch file itself
- `pause` — keep the window open so the user can read the output

The batch file exists solely because double-clicking a `.ps1` file doesn't run it on Windows — it opens in Notepad. The `.bat` wrapper makes it double-clickable.

### `Uninstall.bat` and `Check.bat`

Identical pattern to `Install.bat`, just calling different `.ps1` scripts.

### `payload/zbar.ps1` — The Blocker

This is the core script that runs forever on the target PC. It's intentionally simple (~35 lines).

```powershell
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$blocklistFile = Join-Path $scriptDir "blocklist.txt"
$logFile = Join-Path $scriptDir "zbar-log.txt"
$pidFile = Join-Path $scriptDir "zbar.pid"
```

**Path resolution:** The script uses `$MyInvocation.MyCommand.Path` to find its own location, then derives all other file paths relative to that. This means it works regardless of where it's installed — it always looks for `blocklist.txt` and writes `zbar-log.txt` in the same directory as itself.

```powershell
[IO.File]::WriteAllText($pidFile, $PID.ToString())
```

**PID file:** On startup, writes the current process ID to `zbar.pid` as ASCII text. This is used by the uninstaller and diagnostics to find and kill the running instance. We use `[IO.File]::WriteAllText()` instead of `Out-File` because `Out-File` defaults to UTF-16 encoding on Windows PowerShell 5.1, and batch files can't read UTF-16. This was a bug in an earlier version that caused the uninstaller to fail silently.

```powershell
while ($true) {
    $blocklist = @(Get-Content $blocklistFile -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Trim().ToLower() } |
        Where-Object { $_ -and $_ -notmatch '^\s*#' })
```

**Blocklist reload:** The blocklist is re-read from disk on EVERY cycle (every 5 minutes). This means you can edit the blocklist on the target PC and changes take effect without restarting anything. The blocklist is:
- Read line by line
- Trimmed of whitespace
- Lowercased (for case-insensitive matching)
- Filtered to exclude empty lines and comments (lines starting with `#`)

```powershell
    if ($blocklist.Count -gt 0) {
        foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
            if ($blocklist -contains $proc.ProcessName.ToLower()) {
```

**Process matching:** `Get-Process` returns all running processes. For each one, `ProcessName` (which is the `.exe` name without the `.exe` extension) is lowercased and checked against the blocklist using PowerShell's `-contains` operator. This is an exact match — `steam` matches `steam.exe` but NOT `steamwebhelper.exe`.

```powershell
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
```

**The kill:** `Stop-Process -Force` calls the Windows API `TerminateProcess()`. This is the hardest possible kill — no graceful shutdown, no save prompts, no "are you sure" dialogs. The process dies instantly.

```powershell
                "$now  KILLED  $($proc.ProcessName)  (PID $($proc.Id))" |
                    Out-File $logFile -Append -Encoding utf8
```

**Logging:** Every kill is logged with a timestamp, the process name, and the PID. Failed kills (e.g., process exited between detection and kill) are logged with "FAILED" instead of "KILLED".

```powershell
    Start-Sleep -Seconds 300
```

**The interval:** 300 seconds = 5 minutes. After scanning and killing, the script sleeps for 5 minutes, then does it all again. Forever.

### `payload/blocklist.txt` — The Game List

A plain text file with one process name per line. Comments start with `#`. Process names are WITHOUT the `.exe` extension (because that's how PowerShell's `Get-Process` returns them).

The file is organized by category:

```
# --- Gaming Platforms & Launchers ---
steam
steamwebhelper
steamservice
GameOverlayUI
EpicGamesLauncher
EpicWebHelper
...

# --- Fortnite ---
FortniteClient-Win64-Shipping
FortniteLauncher
...
```

**Currently includes 127 entries** covering:
- 8 gaming platforms (Steam, Epic, Riot, Battle.net, EA, Ubisoft, GOG, Xbox)
- 60+ individual games (Fortnite, Minecraft, Roblox, Valorant, League of Legends, CS2, etc.)
- Associated helper processes, launchers, and anti-cheat processes

### `payload/zbar-install.ps1` — The Installer (~660 lines)

This is the most complex script. It handles:

1. **Self-elevation to admin** via `Start-Process -Verb RunAs`
2. **Cleanup** of any existing installation
3. **File copying** with verification (checks each file exists and has correct size after copy)
4. **Windows Defender exclusion** via `Add-MpPreference -ExclusionPath`
5. **Persistence setup** with 5 fallback methods (see [Persistence Mechanism](#persistence-mechanism))
6. **Immediate process launch**
7. **Post-install verification** (checks files, task, process, blocklist)
8. **Report generation** (writes `install-report.txt` to USB)

Every step is wrapped in `try/catch` with detailed error logging. The script never fails silently.

### `payload/zbar-uninstall.ps1` — The Uninstaller (~414 lines)

Mirrors the installer but in reverse:

1. **Self-elevation to admin**
2. **Removes ALL persistence methods** (scheduled task, registry keys, startup folder entries) — regardless of which method was used to install
3. **Kills all running zbar processes** (both by CommandLine search and PID file)
4. **Removes Windows Defender exclusion**
5. **Deletes the entire install directory**
6. **Verification** that everything is gone
7. **Report generation** (writes `uninstall-report.txt` to USB)

### `payload/zbar-check.ps1` — The Diagnostic Tool (~858 lines)

The most comprehensive file. Performs 10 categories of checks:

1. **Environment** — OS, user, admin status, PowerShell version, .NET version, uptime
2. **Install directory** — file listing with sizes, dates, MD5 hashes, ACL permissions
3. **Core files** — existence and integrity checks
4. **All persistence methods** — scheduled task details, registry keys, startup folder entries
5. **Process status** — finds zbar processes, shows PID, uptime, CommandLine, user
6. **PID file** — validates stored PID against running processes
7. **Kill log** — statistics, top killed processes, last 50 kills with timestamps
8. **Execution policy** — all 5 PowerShell scopes
9. **Potential blockers** — Defender, Group Policy, AppLocker, WDAC, Constrained Language Mode
10. **Task Scheduler deep dive** — service status, task XML dump, trigger details

All output goes to both the console (with colors) and a report file on the USB (`zbar-report.txt`).

---

## The Blocklist

### How process names work on Windows

Every running program on Windows is an `.exe` file. When you open Task Manager and go to the "Details" tab, you see the full filename (e.g., `steam.exe`). PowerShell's `Get-Process` returns the name WITHOUT `.exe` (e.g., `steam`). The blocklist uses this format — no `.exe` extension.

### Process names are NOT always obvious

Many games don't use their own name as the process name:

| Game | Actual Process Name | Why |
|------|-------------------|-----|
| Fortnite | `FortniteClient-Win64-Shipping` | Unreal Engine naming convention |
| Apex Legends | `r5apex` | Internal code name |
| PUBG | `TslGame` | Original Korean name |
| Genshin Impact | `YuanShen` | Chinese name |
| Minecraft (Java) | `javaw` | Runs on Java runtime |
| Call of Duty | `cod` | Abbreviated |
| ARK: Survival Evolved | `ShooterGame` | Unreal Engine default |

### How to find a game's process name

1. Launch the game on any PC
2. Open Task Manager (Ctrl+Shift+Esc)
3. Go to the "Details" tab
4. Find the game in the list
5. The "Name" column shows the `.exe` name
6. Remove the `.exe` and add it to `blocklist.txt`

### How to add a new game

Open `blocklist.txt` on the target PC at:
```
C:\ProgramData\zbar\blocklist.txt
```

Add the process name (without `.exe`) on a new line. You can add a comment above it:

```
# --- My New Game ---
MyNewGame
MyNewGameLauncher
```

Changes take effect within 5 minutes. No restart needed.

### How to STOP blocking a game

Open `blocklist.txt` and either:
- Delete the line
- Comment it out by adding `#` at the start: `# steam`

### Games with multiple processes

Many games have multiple related processes. For thorough blocking, you should block all of them:

**Steam example:**
```
steam              ← Main client
steamwebhelper     ← Built-in browser
steamservice       ← Background service
GameOverlayUI      ← In-game overlay
```

**Epic Games + Fortnite example:**
```
EpicGamesLauncher           ← Launcher
EpicWebHelper               ← Launcher's web engine
FortniteClient-Win64-Shipping  ← The actual game
FortniteLauncher             ← Game launcher stub
```

### The `javaw` problem

Minecraft Java Edition runs as `javaw.exe`. However, `javaw` is the generic Java runtime — blocking it would kill ANY Java application, not just Minecraft. For this reason, `javaw` is commented out in the default blocklist:

```
# javaw  # Minecraft Java Edition — WARNING: also kills any Java app
```

Uncomment it only if you're sure no other Java applications are needed on the PC. Minecraft Bedrock Edition (`Minecraft.Windows`) doesn't have this problem.

### Matching behavior

- Matching is **case-insensitive**: `steam` matches `Steam.exe`, `STEAM.exe`, etc.
- Matching is **exact**: `steam` does NOT match `steamwebhelper`. You need separate entries for each.
- Matching is by **ProcessName only**: it doesn't look at file paths, window titles, or anything else

---

## Installation Deep Dive

### Admin Elevation

The installer needs admin privileges to:
- Create a Scheduled Task
- Add a Windows Defender exclusion
- Write to `C:\ProgramData\zbar\` (though this often works without admin too)

The elevation flow:

```
Install.bat
  └─► powershell zbar-install.ps1
        ├─► Check: Am I admin?
        │     NO ──► Start-Process -Verb RunAs (triggers UAC prompt)
        │              └─► New elevated PowerShell runs zbar-install.ps1
        │                    └─► Am I admin? YES ──► Continue with install
        │     YES ──► Continue with install
        └─► If elevation fails (user cancels UAC):
              └─► Continue without admin, try non-admin methods only
```

### Why batch files don't handle elevation

An earlier version tried to handle elevation in the `.bat` file itself. This was fragile because:
- Batch's quote escaping (`\"`) conflicts with PowerShell's
- The `^` line continuation character is brittle (trailing spaces break it)
- `for /f` has different syntax for files vs strings
- UTF-16 encoding from PowerShell can't be read by batch `for /f`

Moving all logic to `.ps1` files and making the `.bat` files 3-line wrappers eliminated all of these issues.

### File Copy

Files are copied from `<USB>\payload\` to `C:\ProgramData\zbar\`. After each copy, the installer verifies:
- The file exists at the destination
- The file size is greater than 0

### The 5 Persistence Methods

See the next section for full details.

---

## Persistence Mechanism

"Persistence" means "how does zbar start automatically when the PC reboots?" The installer tries 5 methods in order and stops at the first one that works:

### Method 1: Register-ScheduledTask (current user) ← PREFERRED

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '...'
$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit 0 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 999
Register-ScheduledTask -TaskName "zbar" -Action $action ...
```

Creates a task that:
- Triggers at system startup (before anyone logs in)
- Also triggers at user logon (belt and suspenders)
- Runs with no time limit (`ExecutionTimeLimit 0`)
- Restarts within 1 minute if the process dies (up to 999 times)
- Runs on battery power
- Doesn't stop when switching to battery

This is the method that works on Stri's PC. In the diagnostic report, you can see the full XML:

```xml
<Triggers>
    <BootTrigger />
    <LogonTrigger />
</Triggers>
<Settings>
    <RestartOnFailure>
        <Count>999</Count>
        <Interval>PT1M</Interval>
    </RestartOnFailure>
</Settings>
```

### Method 2: Register-ScheduledTask (as SYSTEM)

Same as Method 1 but runs as the SYSTEM account instead of the current user. SYSTEM has higher privileges but some home PCs can't create SYSTEM tasks.

### Method 3: schtasks.exe (command line)

Falls back to the older `schtasks.exe` command-line tool:
```
schtasks /create /tn "zbar" /tr "powershell.exe ..." /sc onlogon /ru SYSTEM /rl highest /f
```

This is less featured (single trigger, no restart policy) but has wider compatibility.

### Method 4: Startup folder

Writes a `.vbs` launcher to the Windows Startup folder:
- First tries: `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\` (all users)
- Falls back to: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\` (current user)

The `.vbs` file:
```vbs
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\ProgramData\zbar\zbar.ps1""", 0, False
```

This is the most primitive method but works without any special permissions.

### Method 5: Registry Run key

Adds a value to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`:
```
zbar = powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\zbar\zbar.ps1"
```

Programs listed here run automatically when the current user logs in.

### Why 5 methods?

Different Windows configurations block different methods:
- **Corporate PCs** might have Group Policy blocking Task Scheduler
- **Home PCs** might not allow SYSTEM tasks
- **Locked-down PCs** might restrict registry access
- **Startup folder** almost always works but is the easiest to discover and remove

By trying all 5, zbar maximizes the chance of successful persistence on any Windows 10/11 PC.

---

## The Kill Loop

### Timing

The loop runs every 300 seconds (5 minutes). This means:
- **Best case:** A game is killed within seconds of the scan (if launched just before a cycle)
- **Worst case:** A game runs for almost 5 minutes before being killed (if launched just after a cycle)
- **Average:** ~2.5 minutes before a game is killed

### Why 5 minutes?

- Short enough that playing a game is impractical (you'd get killed mid-match)
- Long enough that CPU usage is negligible (scanning processes takes milliseconds)
- Can be changed by editing line 34 of `zbar.ps1`: `Start-Sleep -Seconds 300`

### What happens when a game is killed

From the user's (Stri's) perspective:
1. They launch a game
2. The game opens normally
3. Within 5 minutes, the game window suddenly disappears
4. No error message, no notification, no explanation
5. If they relaunch it, the same thing happens again
6. Gaming launchers (Steam, Epic, etc.) also get killed, so they can't even browse game libraries

### The kill mechanism

`Stop-Process -Id <PID> -Force` calls the Windows API function `TerminateProcess()`. This:
- Is immediate — the process doesn't get a chance to save or clean up
- Cannot be blocked by the target process (unlike WM_CLOSE which can be ignored)
- Works on any process the current user owns (and on ANY process if running as SYSTEM/admin)

### What gets logged

Each kill is logged to `C:\ProgramData\zbar\zbar-log.txt`:

```
2026-03-26 16:38:38  KILLED  FortniteClient-Win64-Shipping  (PID 16956)
2026-03-26 16:38:38  KILLED  FortniteLauncher  (PID 17944)
2026-03-26 16:38:38  KILLED  EpicGamesLauncher  (PID 15656)
```

Failed kills (rare — happens when a process exits between detection and kill):
```
2026-03-26 16:38:38  FAILED  SomeProcess  (PID 12345)  Cannot stop process...
```

---

## The Diagnostic System

### Running a check

1. Plug USB into the target PC
2. Double-click `Check.bat`
3. A terminal window opens showing colored diagnostic output
4. Press Enter when done
5. A report file `zbar-report.txt` is saved to the USB

### What it checks (10 sections)

**Section 1: Environment**
- Computer name, Windows version, build number
- Current user and SID
- Whether running as admin
- PowerShell version
- .NET Framework version
- System uptime (useful to see if the PC was recently rebooted)

**Section 2: Install Directory**
- Lists every file with size, date, and MD5 hash
- Shows directory permissions (ACL)
- MD5 hashes let you verify files haven't been tampered with

**Section 3: Core Files**
- Confirms `zbar.ps1` and `blocklist.txt` exist and aren't empty
- Counts active blocklist entries

**Section 4: Persistence Methods**
Checks ALL 5 possible persistence locations:
- Scheduled Task (with full details: state, last run, triggers, principal)
- Registry HKCU Run
- Registry HKLM Run
- All Users Startup folder
- Current User Startup folder
- Summary of which methods are active

**Section 5: Process Status**
- Searches all `powershell.exe` processes for ones running `zbar.ps1`
- Shows PID, uptime, session ID, user, full command line
- If zbar isn't running, shows ALL powershell processes for debugging

**Section 6: PID File**
- Checks if the stored PID matches a running process
- Shows what process actually has that PID

**Section 7: Kill Log**
- Total kills and failures
- Top 10 most-killed processes (shows what games are being blocked most)
- Last 50 kills with timestamps

**Section 8: Execution Policy**
- Shows all 5 PowerShell execution policy scopes
- Flags if any scope is set to Restricted or AllSigned

**Section 9: Potential Blockers**
- PowerShell Constrained Language Mode
- Windows Defender real-time protection and exclusions
- Group Policy script restrictions
- AppLocker policies
- Device Guard / WDAC (Windows Defender Application Control)

**Section 10: Task Scheduler Deep Dive**
- Task Scheduler service status
- Full task details including XML definition
- All triggers, actions, and settings

### The report file

Everything displayed on screen is also written to `zbar-report.txt` on the USB. This lets you:
- Install zbar on a remote PC
- Run the check
- Bring the USB back to your own PC
- Read the report at your leisure
- Share it with someone for troubleshooting

---

## Uninstallation

### What it removes

The uninstaller is thorough. It removes ALL possible traces of zbar:

1. **Scheduled Task** — deleted via both `Unregister-ScheduledTask` and `schtasks /delete`
2. **Registry HKCU Run key** — deleted
3. **Registry HKLM Run key** — deleted (if present)
4. **All Users Startup folder** — `zbar.vbs` deleted
5. **Current User Startup folder** — `zbar.vbs` deleted
6. **Windows Defender exclusion** — removed
7. **Running process** — killed (found by CommandLine search AND PID file)
8. **Install directory** — `C:\ProgramData\zbar\` deleted recursively

It doesn't matter which persistence method was used during installation — the uninstaller removes all of them.

### Verification

After removal, the uninstaller verifies:
- Install directory is gone
- No scheduled task exists
- No registry entries remain
- No startup folder entries remain
- No zbar processes running

### Report

Writes `uninstall-report.txt` to the USB.

---

## Windows Defender Exclusion

### Why it's needed

Windows Defender sometimes flags PowerShell scripts that:
- Run hidden (`-WindowStyle Hidden`)
- Execute on a schedule
- Kill other processes

These are legitimate behaviors for zbar, but they overlap with malware patterns. The Defender exclusion prevents Defender from quarantining or interfering with zbar.

### What the exclusion does

```powershell
Add-MpPreference -ExclusionPath "C:\ProgramData\zbar"
```

This tells Defender to skip scanning anything inside `C:\ProgramData\zbar\`. It does NOT disable Defender for the rest of the system.

### Removal

The uninstaller removes the exclusion:
```powershell
Remove-MpPreference -ExclusionPath "C:\ProgramData\zbar"
```

### Verification

The diagnostic check (Section 9) reports on Defender status and exclusions. However, viewing exclusion details requires admin — the check script runs without admin by default, so it shows "N/A: Must be an administrator to view exclusions". This is cosmetic; the exclusion is there.

---

## Common Modifications

### Change the scan interval

Edit `C:\ProgramData\zbar\payload\zbar.ps1` (or `payload/zbar.ps1` on the USB), line 34:

```powershell
Start-Sleep -Seconds 300    # Change 300 to desired seconds
```

Examples:
- `60` = 1 minute (more aggressive, slightly higher CPU)
- `300` = 5 minutes (default)
- `600` = 10 minutes (more lenient)
- `30` = 30 seconds (very aggressive)

### Add a new game to the blocklist

1. Find the process name (see [The Blocklist](#the-blocklist) section)
2. Edit `C:\ProgramData\zbar\blocklist.txt` on the target PC
3. Add the name on a new line
4. Wait up to 5 minutes

### Remove a game from the blocklist

Edit `blocklist.txt` and delete the line, or comment it out with `#`.

### Block ALL web browsers (nuclear option)

Add to `blocklist.txt`:
```
# --- Browsers ---
chrome
msedge
firefox
brave
opera
```

WARNING: This blocks ALL browser usage, not just gaming.

### Change the install location

In `zbar-install.ps1`, change the `$installDir` variable near the top:
```powershell
$installDir = "C:\ProgramData\zbar"   # Change to desired path
```

You'll also need to update `zbar-check.ps1` and `zbar-uninstall.ps1` (they have the same variable).

### Make it scan immediately on startup (no 5-minute wait)

The current code already does this — the first scan runs immediately when the script starts. The 5-minute sleep happens AFTER each scan, not before.

### Add a notification when a game is killed (for debugging)

Add this inside the kill block in `zbar.ps1`:

```powershell
# After the Stop-Process line:
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
[System.Windows.Forms.MessageBox]::Show("Blocked: $($proc.ProcessName)", "zbar")
```

Remove this before deploying — it's only for testing. The popup would reveal zbar's existence.

### Run as a different user

In `zbar-install.ps1`, when creating the scheduled task, you can specify a different principal:

```powershell
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
```

Or a specific user:
```powershell
$principal = New-ScheduledTaskPrincipal -UserId "DESKTOP-PC\Username" -RunLevel Highest
```

### Reduce the auto-restart count

In `zbar-install.ps1`, find the `RestartCount` setting:
```powershell
-RestartCount 999    # Change to desired count
```

### View the kill log without the USB

On the target PC, open PowerShell or Command Prompt:
```
type C:\ProgramData\zbar\zbar-log.txt
```

Or in PowerShell:
```powershell
Get-Content C:\ProgramData\zbar\zbar-log.txt | Select-Object -Last 20
```

---

## Troubleshooting Guide

### "Install.bat does nothing / closes immediately"

**Cause:** PowerShell execution policy is blocking the script.
**Fix:** Right-click `Install.bat` → "Run as administrator". If that doesn't work, open PowerShell as admin and run:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

### "Scheduled task not found after install"

**Cause:** Admin elevation failed or was cancelled.
**Fix:** Right-click `Install.bat` → "Run as administrator" to force elevation.

### "zbar is not running after reboot"

**Check 1:** Run `Check.bat` and look at Section 4 (Persistence Methods). Is any method active?
**Check 2:** Look at Section 10 (Task Scheduler). Is the task there? What's the LastResult?
- LastResult `267009` = still running (normal)
- LastResult `0` = completed successfully (might need to check triggers)
- LastResult `2147942401` = access denied (permission issue)

**Fix:** Re-run `Install.bat` as administrator.

### "A game isn't being blocked"

**Check 1:** Is the correct process name in `blocklist.txt`?
**Check 2:** Open Task Manager → Details tab while the game is running. Find the exact `.exe` name.
**Fix:** Add the correct process name (without `.exe`) to `blocklist.txt`.

### "zbar is killing something it shouldn't"

**Fix:** Open `blocklist.txt` and remove or comment out the offending entry.

Common false positives:
- `javaw` — kills all Java apps, not just Minecraft
- `ShooterGame` — generic Unreal Engine name, might match non-gaming UE apps
- `cod` — very short, but unlikely to conflict with anything else

### "Check.bat shows warnings about Defender"

**The warning:** "Install directory is NOT excluded from Defender"
**Explanation:** The check runs without admin and can't see Defender exclusions. The exclusion IS there (added during install), but the check can't verify it. This is cosmetic. If zbar is running, Defender isn't blocking it.

### "Check.bat shows Device Guard / WDAC warning"

**Explanation:** Device Guard / Virtualization Based Security is standard on Windows 11. It doesn't block PowerShell scripts running with `-ExecutionPolicy Bypass`. This warning is informational only.

### "The install report shows failures"

Read the specific error messages. Common issues:
- "Access denied" — need admin. Re-run as administrator.
- "File not found" — USB was disconnected during install, or payload folder is damaged.
- "The term 'Register-ScheduledTask' is not recognized" — PowerShell version too old (need 4.0+). The installer will fall back to other methods.

### "I want to reinstall / update the blocklist from USB"

Just run `Install.bat` again. It kills the existing instance, removes the old task, copies fresh files, and sets everything up again.

---

## Design Decisions and History

### Why PowerShell?

- Available on every Windows 10/11 PC (no additional runtime needed)
- Can kill processes, create scheduled tasks, modify registry, and interact with Defender
- `-WindowStyle Hidden` makes it invisible
- `-ExecutionPolicy Bypass` overrides any script restrictions

### Why not compile to .exe?

An earlier design considered compiling to a Go/C#/Rust binary. PowerShell was chosen because:
- No build step needed — the scripts ARE the product
- Easy to inspect and modify (it's just text files)
- No antivirus false positives from unsigned executables (though Defender can still flag scripts)
- No dependency on compilers or build tools

### Why not a Windows Service?

Windows Services require:
- A proper service executable (not a script)
- Service registration with specific APIs
- More complex installation
- More complex debugging

Task Scheduler + PowerShell achieves the same result with much less complexity.

### Version History

**v1 (initial):**
- Registry Run key for persistence
- VBScript launcher (`.vbs`) to hide the PowerShell window
- Inline PowerShell in batch files with `^` continuation
- Simple Check.bat with inline PowerShell

**v1 problems:**
- PID file written as UTF-16 (batch couldn't read it)
- `for /f` missing `usebackq` (broke on paths with spaces)
- Check.bat crashed (inline PowerShell with `^` continuation was fragile)
- Registry Run key didn't persist on Stri's PC

**v2 (current):**
- All logic moved to `.ps1` files
- Batch files are 3-line wrappers
- 5 fallback persistence methods
- Self-elevation in PowerShell (not batch)
- Comprehensive 858-line diagnostic tool
- Install/uninstall reports written to USB
- Windows Defender exclusion
- VBScript launcher removed (Task Scheduler handles hidden execution)

### The elevation saga

The biggest technical challenge was reliable admin elevation. Batch file elevation using `powershell -Command "Start-Process '%~f0' -Verb RunAs"` was unreliable because:
1. Batch `\"` escaping conflicts with PowerShell string parsing
2. The elevated process might start in a different working directory
3. `%~dp0` (batch path variable) doesn't survive all elevation methods
4. UTF-16 vs ASCII encoding issues between PowerShell and batch

The fix was moving elevation to PowerShell itself, where `Start-Process -Verb RunAs` is a first-class operation with proper argument passing.

---

## Security Considerations

### Who can remove zbar?

Anyone with admin access to the PC. The Scheduled Task can be seen in Task Scheduler (`taskschd.msc`), the files are in `C:\ProgramData\zbar\`, and `powershell.exe` is visible in Task Manager. A tech-savvy user who knows where to look can remove it.

This is by design — zbar is not meant to survive active removal attempts.

### What zbar can see

- Process names and PIDs (via `Get-Process`)
- Nothing else. It doesn't read files, network traffic, keystrokes, or screen content.

### What zbar modifies

- Kills processes (the ONLY system modification)
- Writes to its own log file
- Writes to its own PID file
- Has a Defender exclusion for its own directory

### What zbar CANNOT do

- It cannot block games from being installed (only from running)
- It cannot block web-based games (unless you add browser process names)
- It cannot prevent a user from editing the blocklist (if they find it)
- It cannot prevent a user from killing it in Task Manager (though it auto-restarts)
- It cannot survive if a user deletes the scheduled task and the install directory

### Network activity

zbar makes ZERO network connections. It doesn't check for updates, send telemetry, or phone home. Everything is local.

---

## Technical Reference

### PowerShell Version Requirements

- **Minimum:** PowerShell 4.0 (for `Register-ScheduledTask`)
- **Recommended:** PowerShell 5.1 (ships with Windows 10/11)
- **Tested on:** PowerShell 5.1.26100 (Windows 11 Pro, build 26200)

If `Register-ScheduledTask` is unavailable (PS < 4.0), the installer falls back to `schtasks.exe`, startup folder, or registry.

### Windows Version Requirements

- **Minimum:** Windows 10
- **Recommended:** Windows 10/11
- **Tested on:** Windows 11 Pro 10.0.26200

### Key Windows APIs / Commands Used

| Operation | Command/API | Used in |
|-----------|------------|---------|
| Kill process | `Stop-Process -Force` → `TerminateProcess()` | zbar.ps1 |
| List processes | `Get-Process` | zbar.ps1 |
| Create scheduled task | `Register-ScheduledTask` | zbar-install.ps1 |
| Run scheduled task | `schtasks /run` | zbar-install.ps1 |
| Add Defender exclusion | `Add-MpPreference -ExclusionPath` | zbar-install.ps1 |
| Admin check | `WindowsPrincipal.IsInRole()` | all install/uninstall |
| Elevation | `Start-Process -Verb RunAs` | all install/uninstall |
| Find process by cmdline | `Get-CimInstance Win32_Process` | check/uninstall |
| Registry modification | `Set-ItemProperty` / `Remove-ItemProperty` | install/uninstall |
| File hashing | `Get-FileHash -Algorithm MD5` | zbar-check.ps1 |

### Task Scheduler XML Schema

The full task definition as created by the installer:

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <UserId>{USER-SID}</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>          <!-- No time limit -->
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure>
      <Count>999</Count>                                    <!-- Restart up to 999 times -->
      <Interval>PT1M</Interval>                            <!-- Wait 1 minute between restarts -->
    </RestartOnFailure>
    <StartWhenAvailable>true</StartWhenAvailable>          <!-- Run if a trigger was missed -->
  </Settings>
  <Triggers>
    <BootTrigger />                                         <!-- Run at system startup -->
    <LogonTrigger />                                        <!-- Run at user logon -->
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\zbar\zbar.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
```

### Log File Format

```
{YYYY-MM-DD HH:MM:SS}  {KILLED|FAILED}  {ProcessName}  (PID {number})
```

Example:
```
2026-03-26 16:38:38  KILLED  FortniteClient-Win64-Shipping  (PID 16956)
2026-03-26 16:38:38  FAILED  SomeProcess  (PID 12345)  Access is denied.
```

### PID File Format

Plain ASCII text containing a single integer (the process ID):
```
8940
```

Written by `[IO.File]::WriteAllText()` to ensure ASCII encoding (not UTF-16).

### Exit Codes

| Script | Exit 0 | Exit 1 |
|--------|--------|--------|
| zbar-install.ps1 | All critical steps passed | Any critical failure |
| zbar-uninstall.ps1 | Everything removed | Some removals failed |
| zbar-check.ps1 | Always exits 0 (informational) | N/A |
| zbar.ps1 | N/A (runs forever) | N/A |

---

## Full Process List (as of latest version)

The complete blocklist with 127 entries, organized by category:

### Gaming Platforms & Launchers (24 entries)
`steam`, `steamwebhelper`, `steamservice`, `GameOverlayUI`, `EpicGamesLauncher`, `EpicWebHelper`, `RiotClientServices`, `RiotClientUx`, `RiotClientCrashHandler`, `vgtray`, `Battle.net`, `BlizzardBrowser`, `EADesktop`, `EABackgroundService`, `EAConnect_microsoft`, `Origin`, `OriginWebHelperService`, `UbisoftConnect`, `upc`, `UplayWebCore`, `GalaxyClient`, `GalaxyClientHelper`, `GameBar`, `GameBarPresenceWriter`

### Individual Games (103 entries)
`FortniteClient-Win64-Shipping`, `FortniteLauncher`, `Minecraft.Windows`, `MinecraftLauncher`, `RobloxPlayerBeta`, `RobloxPlayerLauncher`, `VALORANT-Win64-Shipping`, `VALORANT`, `LeagueClient`, `LeagueClientUx`, `League of Legends`, `cs2`, `r5apex`, `cod`, `ModernWarfare`, `cod23-cod`, `BlackOpsColdWar`, `GTA5`, `PlayGTAV`, `GTAVLauncher`, `Overwatch`, `RocketLeague`, `dota2`, `TslGame`, `PUBG-Win64-Shipping`, `eldenring`, `bg3`, `bg3_dx11`, `HogwartsLegacy`, `GenshinImpact`, `YuanShen`, `destiny2`, `RainbowSix`, `RainbowSix_BE`, `FC24`, `FC25`, `FIFA23`, `FIFA24`, `Madden24`, `Madden25`, `NBA2K24`, `NBA2K25`, `NBA2K26`, `Diablo IV`, `Wow`, `WowClassic`, `Starfield`, `Cyberpunk2077`, `TS4_x64`, `Palworld-Win64-Shipping`, `Lethal Company`, `Among Us`, `FallGuys_client_game`, `DeadByDaylight-Win64-Shipping`, `RustClient`, `ShooterGame`, `ArkAscended`, `Terraria`, `Stardew Valley`, `HaloInfinite`, `SoTGame`, `MonsterHunterWorld`, `MonsterHunterRise`, `Tekken8`, `TEKKEN 8`, `StreetFighter6`, `MK1`, `CivVI`, `Warhammer3`, `Warhammer2`, `Rome2`, `stellaris`, `hoi4`, `Warframe.x64`, `PathOfExile`, `PathOfExileSteam`, `PathOfExile_x64Steam`, `LOSTARK`, `ffxiv_dx11`, `EscapeFromTarkov`, `DayZ`, `DayZ_BE`, `ReadyOrNot-Win64-Shipping`, `HLL-Win64-Shipping`, `FSD-Win64-Shipping`, `Phasmophobia`, `FactoryGame-Win64-Shipping`, `factorio`, `Cities2`, `eurotrucks2`, `FlightSimulator`, `Wuthering Waves`, `WutheringWaves`, `ZenlessZoneZero`, `StarRail`, `TheFinals`, `Discovery`, `Naraka-Win64-Shipping`, `GranblueFantasyRelink`, `TEKKEN 7`, `DragonBallFighterZ`, `Pal-Win64-Shipping`, `SatisfactoryEarlyAccess-Win64-Shipping`
