# Sameru

**Keep awake. Keep cool.**

A small macOS menu bar app with three things and nothing else: keep the Mac awake,
black out the screen so you can wipe it down, and pin the fans.

Written in Objective-C, no dependencies.

## The name

*Sameru* (さめる) is two Japanese verbs that happen to sound the same:

- **覚める** — to wake, to stay awake → Keep Awake
- **冷める** — to cool down → Fan Control

One word covers both halves of what the app does, rather than bolting two
unrelated ideas together — which is why it won over `Soyogi` (そよぎ, a light
breeze), `Ibuki` (息吹, breath), and `Mezame` (目覚め, awakening). Written
**Sameru**, occasionally **さめる**.

Clean mode is the odd one out, but it follows from the other two: the app already
has to hold the screen awake and swallow input to do its job.

## Install

With Homebrew:

```sh
brew install --cask owo-network/brew/sameru
```

Or download the latest `.dmg` from
[Releases](https://github.com/missuo/Sameru/releases) and drag Sameru to
Applications.

Builds are signed with a Developer ID certificate and notarized by Apple, so they
open without a Gatekeeper warning.

Requires macOS 14 or later on Apple silicon.

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
| **Cool** | Pins every fan 40% of the way up its own range |
| **Max** | Pins every fan at its hardware maximum (`F<n>Mx`) |

Cool is a point along each fan's usable range — `min + 0.4 × (max − min)` — rather
than a fixed RPM or a share of the ceiling, because **both** ends of that range vary
per model:

| | Floor (`F<n>Mn`) | Ceiling (`F<n>Mx`) | Cool |
| --- | --- | --- | --- |
| M1 Pro MacBook Pro | 1200 | 5779 / 6241 | 3032 / 3216 |
| M4 Pro MacBook Pro | 2317 | 7826 | 4521 |

A fixed RPM would sit barely above idle on a machine whose fans never drop below
2317, and a share of the ceiling lands near full speed wherever the ceiling is high
(75% of 7826 is 5870 RPM, which is not "cool"). Every target is clamped to that
fan's own reported min and max.

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

The app is not sandboxed — event taps, launching the helper, and the privileged
install cannot work inside the sandbox. It does run under the hardened runtime,
which is what notarization requires.

The project is stored in Xcode's format 77 so that released Xcode versions (and CI
runners) can open it. Xcode 27 betas will silently rewrite it to format 110 on
save, which nothing else can read — if a build starts failing with *"a future Xcode
project file format"*, set `objectVersion` back to `77` in `project.pbxproj`.

Tagging `v*` runs `.github/workflows/release.yml`, which signs the helper and app,
notarizes and staples both the app and the DMG, and publishes a GitHub release.

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

## Credits

Sameru is a much smaller take on ideas from
[MacTools](https://github.com/ggbond268/MacTools) by ggbond268, which is licensed
under Apache 2.0. The Swift plugins there were the reference for the parts that
talk to the hardware, reimplemented here in Objective-C:

- **SMC access** — the `SMCKeyData` struct layout, the `flt` / `fpe2` / `sp78`
  encodings, and the `FNum` / `F<n>Ac` / `F<n>Mn` / `F<n>Mx` / `F<n>Md` / `F<n>Tg`
  key handling
- **The privileged helper** — shipping a small tool inside the bundle and
  installing it setuid root behind a single authorization prompt, verifying it
  against the bundled copy before each run
- **Clean mode** — the `CGEventTap` structure, and the emergency exit paths for
  session lock, display sleep and a tap the system disables

Sameru differs in scope and in a few decisions: three features instead of forty,
no plugin architecture, "cool" as a point along each fan's usable range rather
than a fixed RPM, and a popover panel instead of a menu.

## License

[Apache 2.0](LICENSE), the same licence as MacTools, which parts of this code are
derived from.
