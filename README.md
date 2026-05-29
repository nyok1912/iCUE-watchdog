# iCUE Watchdog

> Automatically fixes the internal IPC communication failure in iCUE 5 that causes
> Corsair devices to disappear after waking the PC from sleep, resuming from
> hibernation, or unlocking a Windows session. When it happens, iCUE loses control
> over **RGB lighting, fan profiles, and RAM** across all managed devices.

---

## The problem

If you have Corsair devices running iCUE 5, you've probably seen this: you turn on
your monitor, unlock Windows, and suddenly nothing has lighting anymore. You open
iCUE and the device list is empty — as if nothing is plugged in. The devices are
physically connected and Windows recognises them just fine, but iCUE says there's
nothing there.

But this isn't just a cosmetic issue. iCUE also manages the **fan speed curves** of
every fan connected to your controllers (Commander Core XT, iCUE LINK System Hub)
and the **RGB lighting of your RAM modules**. When iCUE loses communication, **all
those profiles stop being applied**: fans fall back to BIOS-defined fixed speeds
(sometimes too loud, sometimes too slow) and your RAM reverts to static colour or
turns off entirely.

The temporary fix is to close and reopen iCUE — sometimes twice. Depending on how
long it takes you to notice, you've been sitting there for ten minutes with static
white lighting and your fans running on BIOS defaults, and nothing warned you.

This happens reproducibly:

- When the PC wakes from sleep (S3)
- When resuming from hibernation
- When turning the monitor back on after it has been off
- After any system power event (resume from low-power state)

---

> **A personal note:** there is a certain bitter irony in high-end hardware explicitly
> designed for full iCUE integration failing silently and repeatedly at something as
> routine as turning your monitor back on. Corsair has been aware of this bug for years
> and the response has been incomplete patches or outright silence. When you deliberately
> build an entire system — fan controllers, hub, liquid cooling, RAM — from the same
> manufacturer precisely to get centralised, integrated control, the very least you
> should expect is that the integration actually works without having to install
> third-party workarounds just to keep it running. In that regard, Corsair has let
> its customers down, and that is simply not good enough.

---

## Why it happens

iCUE 5 is split into two layers that communicate with each other via IPC
(Inter-Process Communication): a low-level service that talks to the USB hardware,
and the UI that shows devices. When the system enters sleep and then wakes up,
Windows re-enumerates the USB devices — but iCUE loses the state of that internal
communication channel and cannot recover it on its own.

The iCUE log makes this explicit. A healthy session looks like this:

```
[...] Entering working state
[...] StartEnumeration finished
[...] cue.devices.set: K70 RGB PRO (...)
[...] Devices ready received from service
```

After waking from sleep, instead:

```
[...] Leaving working state
[...] ConnectionLost
[...] StopEnumeration finished
[...] Disable all enumerators
```

The log records that iCUE detected an IPC connection loss and detached from the
hardware. Until the process is restarted, the devices remain invisible.

---

## Why the usual fixes don't work

Reddit and the Corsair forums always cycle through the same suggestions. None of them
work because **they all target the hardware layer**, but the failure is inside iCUE's
software.

### ❌ Disable USB selective suspend

> Control Panel → Power Options → Change plan settings →
> Change advanced power settings → USB settings →
> USB selective suspend setting → **Disabled**

USB selective suspend lets Windows individually suspend USB ports that are not in
active use, to save power. Disabling it means USB ports will never be suspended.

**Why it doesn't work:** The problem is not that the device disconnects from USB.
After the PC wakes, Windows re-enumerates the devices correctly — you can see them
in Device Manager, they're still there. The failure is that iCUE loses its internal
IPC communication and doesn't restore it. Even if USB ports never sleep, iCUE will
still fail on wake.

### ❌ Uncheck "Allow the computer to turn off this device to save power"

> Device Manager → [Corsair device] → Properties →
> Power Management → uncheck the box

This option tells the USB driver not to power down the device when the system reduces
power. The affected devices detected on a system running this setup are:

**USB controllers (visible in Device Manager → USB tree):**

| Full Hardware ID                       | Device                                    | iCUE function                            |
|----------------------------------------|-------------------------------------------|------------------------------------------|
| `USB\VID_1B1C&PID_0C2A&REV_0100`       | **CORSAIR iCUE COMMANDER CORE XT** (root) | Fan hub and RGB channels — root node     |
| `USB\VID_1B1C&PID_0C2A&REV_0100&MI_00` | COMMANDER CORE XT — interface MI_00       | Corsair proprietary HID (UP:FF42 U:0001) |
| `USB\VID_1B1C&PID_0C2A&REV_0100&MI_01` | COMMANDER CORE XT — interface MI_01       | Active iCUE control (UP:FF42 U:0002)     |
| `USB\VID_1B1C&PID_0C3F&REV_0100`       | **CORSAIR iCUE LINK System Hub** (root)   | iCUE LINK ecosystem hub — root node      |
| `USB\VID_1B1C&PID_0C3F&REV_0100&MI_00` | iCUE LINK System Hub — interface MI_00    | Corsair proprietary HID (UP:FF42 U:0001) |
| `USB\VID_1B1C&PID_0C3F&REV_0100&MI_01` | iCUE LINK System Hub — interface MI_01    | Active iCUE control (UP:FF42 U:0002)     |

**RAM (controlled via SMBus/I2C — does not appear in the USB device tree):**

| Part number          | Device                                              | iCUE function                  |
|----------------------|-----------------------------------------------------|--------------------------------|
| `CMT32GX5M2B5600C36` | **Corsair DOMINATOR TITANIUM** DDR5-5600 16 GB each | RGB lighting of the modules    |

> **VID `1B1C`** = Corsair Memory Inc. (official USB Vendor ID).  
> **`UP:FF42`** is Corsair's proprietary HID usage page. Only iCUE knows how to
> interpret messages on this interface; when iCUE loses IPC, the devices are
> completely inert until the process restarts.
>
> The RAM **has no entry in the USB device tree** because iCUE controls it directly
> via the motherboard's SMBus/I2C bus, accessing the modules' internal registers
> without going through Windows' USB subsystem at all. This means the "Allow the
> computer to turn off this device" checkbox does not even exist for it — its
> lighting also disappears when iCUE's IPC fails, and it also cannot be "fixed" with
> any system power setting.

**Why it doesn't work:** Same as before — the hardware doesn't physically disconnect.
iCUE is the one losing the thread internally. You can uncheck every power management
box on every Corsair device and the next morning you'll have exactly the same problem.

### ❌ Restart the Corsair service

Some posts suggest restarting `CorsairService` or `CorsairLLAService` from Task
Manager or `services.msc`. This may occasionally work but is inconsistent and
requires manual intervention. In many cases restarting the service without restarting
the main iCUE process does not resolve the IPC failure.

### ❌ Reinstall iCUE / update drivers

This bug has been present in iCUE 5 since its early versions. iCUE updates have not
permanently fixed it — if they had, it would be gone by now. Reinstalling does not
change how the software behaves in response to system power events.

---

## The real fix: restart iCUE

The only thing that works consistently is killing the `iCUE.exe` process and
relaunching it. When iCUE starts fresh, it initialises its IPC layer cleanly and
finds all devices without issue.

**iCUE Watchdog** automates exactly that. It reads iCUE's own log to detect
whether an IPC failure has actually occurred, and if it has, kills the process and
relaunches it — no manual intervention, no noticing that something went wrong.

---

## How it works

The `Restore.ps1` script does the following:

1. Locates the most recent iCUE log file (in `%LOCALAPPDATA%\Corsair\Logs\CUE5\` if
   iCUE runs without elevation, or `C:\ProgramData\Corsair\Logs\CUE5\` if elevated).
2. Reads the last 200 lines and looks for IPC state markers:
   - `Entering working state` / `StartEnumeration finished` → iCUE OK
   - `Leaving working state` / `ConnectionLost` / `StopEnumeration finished` /
     `Disable all enumerators` → iCUE has lost IPC
3. If the last event is a loss or exit marker, the failure is confirmed: kills
   `iCUE.exe` and relaunches it via `Shell.Application.ShellExecute` to ensure it
   starts without administrator privileges (required for iCUE to communicate with
   USB devices correctly).
4. If iCUE resists being closed, requests UAC elevation **exclusively** to kill the
   process, then continues without elevated privileges.

The scheduled task fires automatically in two situations:

- **On session unlock** — covers the scenario of turning the monitor back on and
  unlocking Windows.
- **Power Troubleshooter event ID 1** — fires when Windows logs a resume from sleep
  or hibernation.

---

## Installation

### Option A — All-in-one (recommended)

Download `iCUE-Watchdog.cmd` from the [Releases] section and double-click it. A menu
appears:

```
==========================================
      iCUE Watchdog  v1.0
==========================================

 [1] Install   (register Scheduled Task)
 [2] Restore   (force restart)
 [3] Uninstall (remove task and files)
 [0] Exit
```

Select **[1] Install**. UAC will prompt for confirmation to register the scheduled
task. After installing, the fixer will run automatically on every resume.

### Option B — Separate files

Download the files from `Separate-Files-Version\`:

| File             | Description                                      |
|------------------|--------------------------------------------------|
| `Install.cmd`    | Registers the scheduled task (requires UAC)      |
| `Restore.cmd`    | Manually triggers a forced iCUE restart cycle    |
| `Uninstall.cmd`  | Removes the task and installed files             |

### Where it installs

The installer copies `Restore.ps1` to:

```
%LOCALAPPDATA%\iCUE-Watchdog\Restore.ps1
```

And registers a scheduled task named `iCUE-Watchdog` with the following properties:

- Runs with the minimum required privileges (`LeastPrivilege`)
- Uses the current user's interactive token (not an invisible background session)
- Triggers on session unlock and on the system power resume event

---

## Uninstall

Run `iCUE-Watchdog.cmd → [3] Uninstall` or `Uninstall.cmd`. The scheduled task and
installation directory will be removed.

---

## Manual use

To run it immediately without waiting for the next unlock:

```cmd
:: From the download folder:
Restore.cmd

:: Force restart without checking the log:
Restore.cmd --force
```

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 (included with Windows)
- iCUE 5 installed in the standard location
- Corsair devices connected via USB

---

## ⚠️ Known limitation: Remote Desktop (RDP)

If you connect to the machine via Remote Desktop, iCUE loses the interactive session
of the physical console user and **does not detect devices** for the duration of the
RDP session. iCUE Watchdog cannot fix this — it is not an IPC failure; iCUE simply
has no access to the session context it needs to talk to the hardware.

I have tried several approaches without success. If anyone has found a way to make
iCUE detect devices during an active RDP session, any input is welcome in the
[repository Issues](https://github.com/nyok1912/iCUE-watchdog/issues).

---

## Security

- The script **never** runs with administrator privileges permanently. The only
  exception is killing the iCUE process if it is running elevated, for which a
  short-lived elevated subprocess is spawned to do only that operation.
- Does not modify the Windows registry beyond registering the scheduled task.
- Does not touch Corsair services (only kills `iCUE.exe`).
- Does not send data to any external server.
- Full source code is available in this repository for review.

---

## Build from source

```powershell
# Generate distributable files in build\
.\build.ps1

# Run the test suite
.\test.ps1
```

Distributable files are generated in `build\Separate-Files-Version\` and
`build\All-In-One-Version\`.

---

## License

MIT — see [LICENSE](LICENSE).

[Releases]: https://github.com/nyok1912/iCUE-watchdog/releases
