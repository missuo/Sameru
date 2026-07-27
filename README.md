# Sameru

A small macOS menu bar app with three things and nothing else: keep the Mac awake,
black out the screen so you can wipe it down, and pin the fans.

Written in Objective-C, no dependencies.

## Features

### Keep Awake

Holds `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep` power
assertions, so the Mac and its display stay on. Roughly `caffeinate -di`, released
as soon as you flip the switch back or quit.

### Clean Mode

Blacks out every screen and swallows all keyboard, trackpad and mouse input so you
can clean the machine without triggering anything.

Exit with **⌃⌘⎋** or by holding the right mouse button for 3 seconds. It also exits
on its own if the session locks, the display sleeps, a screen is disconnected, or
the input tap is disabled by the system.

Requires Accessibility permission (System Settings › Privacy & Security ›
Accessibility), which macOS will prompt for on first use.

### Fan Control

Three modes, one click each:

| Mode | Effect |
| --- | --- |
| **Auto** | Hands the fans back to macOS (`F<n>Md = 0`) |
| **Cool** | Pins every fan at 75% of its own maximum |
| **Max** | Pins every fan at its hardware maximum (`F<n>Mx`) |

Cool is a *fraction* rather than a fixed RPM because the ceiling differs per model —
one MacBook Pro reports 5779 and 6241 RPM for its two fans, while other Macs top out
well under 4000. Every target is clamped to that fan's reported min and max.

The panel shows live per-fan RPM and CPU temperature, refreshed every 2 seconds
while it is open. The chosen mode is remembered, restored to Auto on quit, and
re-armed on launch and on wake — the SMC does not always keep a forced target
across a sleep cycle.

Writing SMC keys needs root, so a small helper (`sameru-fan-helper`) ships inside
the app bundle and is installed setuid root to
`/Library/PrivilegedHelperTools/` on first use, behind one admin prompt. Before
installing, Sameru verifies its own code signature; before running, it compares the
installed copy byte for byte against the bundled one, so a stale or tampered root
binary is never executed. Reading fan speeds needs no privileges and is done
in process.

## Building

```sh
xcodebuild -project Sameru.xcodeproj -scheme Sameru -configuration Release build
```

Requires Xcode 27 or later. The app is not sandboxed — event taps, launching the
helper, and the privileged install cannot work inside the sandbox.

## Layout

| Path | Purpose |
| --- | --- |
| `Sameru/AppDelegate.m` | Status item and popover host |
| `Sameru/SMRPanelViewController.m` | The translucent panel |
| `Sameru/SMRKeepAwakeController.m` | IOKit power assertions |
| `Sameru/SMRCleanModeController.m` | Event tap and screen overlays |
| `Sameru/SMRFanController.m` | Fan modes, helper install and invocation |
| `Sameru/SMRSMCReader.m` | Read-only AppleSMC access |
| `Sameru/SMRLoginItemController.m` | `SMAppService` login item |
| `FanHelper/main.m` | Privileged SMC helper tool |
