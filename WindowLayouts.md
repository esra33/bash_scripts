# Window Layouts

Save the position of every app window across all your displays and desktops (Spaces) into named JSON profiles, then restore them later.

```bash
SaveWindowLayout work       # capture the current layout
LoadWindowLayout work       # put every window back
```

## Setup

1. `WindowLayouts.sh` is sourced by `RefreshScripts` in `bash_profile`, so the commands are available in every new shell. Run `RefreshScripts` to pick up changes in an open shell.
2. Give your terminal app Accessibility access: **System Settings › Privacy & Security › Accessibility**, then restart the terminal. The first save or load prompts for it if it is missing.
3. The first command compiles `WindowLayoutHelper.swift` (about 30 seconds). It is rebuilt automatically whenever the Swift file changes.

Requirements: macOS with the Xcode Command Line Tools (`swiftc`) and `jq`, both already installed.

## Commands

Every command accepts `-h` or `--help`.

| Command | What it does |
| --- | --- |
| `SaveWindowLayout <name>` | Saves all app windows to a profile. Overwrites a profile with the same name. |
| `LoadWindowLayout <name> [--dry-run] [--launch] [--move-desktops]` | Moves and resizes windows to match a profile. |
| `ListWindowLayouts` | Lists profiles with window count, displays and save date. |
| `ShowWindowLayout <name>` | Shows a profile's windows grouped by display and desktop. |
| `DeleteWindowLayout <name>` | Permanently deletes a profile. |
| `ListDesktops` | Lists desktops with their "Switch to Desktop N" number and whether that shortcut is on. |

### Load options

| Option | Effect |
| --- | --- |
| `--dry-run` | Prints where each window would go. Nothing moves. |
| `--launch` | Opens apps from the profile that are not running, waits for them, then places their windows. |
| `--move-desktops` | Moves windows that are on the wrong desktop. The screen switches desktops while it works, about 1.5 seconds per window. See [Moving windows between desktops](#moving-windows-between-desktops). |

### Examples

```bash
SaveWindowLayout work
SaveWindowLayout "deep focus"
SaveWindowLayout laptop-only

ListWindowLayouts
# deep focus   6 windows   Built-in Retina Display, Pavilion 27q (1)                      2026-10-06T18:00:00Z
# work         12 windows  Built-in Retina Display, Pavilion 27q (2), Pavilion 27q (1)   2026-10-06T17:42:10Z

ShowWindowLayout work
# Built-in Retina Display - desktop 1
#   Slack: general  [0,33 1728x992]
# Pavilion 27q (1) - desktop 2
#   JetBrains Rider: TripleMatch3D  [0,30 2560x1410]

LoadWindowLayout work --dry-run
LoadWindowLayout work --launch --move-desktops
DeleteWindowLayout laptop-only
```

## What gets saved

Each profile records, for every standard window of every regular app:

- App name and bundle id
- Window title and window id
- Display (UUID and name) and desktop number on that display
- Position and size, both absolute and relative to the display
- Whether the window is full screen or minimized

Windows on desktops you are not currently viewing are included.

## How loading works

1. **Matching windows.** Saved windows are matched to open ones from the same app: first by window id and title, then by title, then in order. Apps whose titles change (browsers, editors) still get matched.
2. **Picking the display.** The saved display is found by UUID, then by name, then falls back to the main display. Positions are relative to the display, so rearranging monitors in System Settings doesn't break a profile. Windows are shrunk to fit if the target display is smaller.
3. **Desktop.** If a window is on a different desktop than saved, it is moved there with yabai or `--move-desktops` (see below), or listed at the end of the output.
4. **Placing.** The window is moved and resized. Its full screen and minimized state are restored.

Windows that are not open are reported as `missing`. Use `--launch` to open their apps first.

## Moving windows between desktops

Since macOS 14.5, Apple blocks other apps from moving windows between desktops directly. Without help, every window is placed and sized correctly on the desktop it is on, but one sitting on the wrong desktop stays there and is listed so you can drag it over:

```
These windows are on a different desktop than saved. ...
  Slack - general (on desktop 1, saved on Built-in Retina Display, desktop 3)
```

There are two ways to automate this step.

### `--move-desktops` (no extra software)

macOS still lets an app move a window onto another display, and the window lands on whichever desktop that display is showing. `--move-desktops` uses the "Switch to Desktop N" keyboard shortcuts to show the right desktop first:

- **Moving to another display:** shows the window's current desktop, switches the target display to the saved desktop, then moves the window there.
- **Moving within one display:** parks the window on another display, switches its own display to the saved desktop, then moves it back.

Afterwards every display goes back to the desktop it was showing. Expect the screen to flip between desktops for about 1.5 seconds per window.

Setup:

1. Turn on the shortcuts in **System Settings › Keyboard › Keyboard Shortcuts › Mission Control**: tick "Switch to Desktop 1", "Switch to Desktop 2" and so on, one per desktop. The keys can be anything. A desktop only gets a "Switch to Desktop" entry once it exists.
2. Run `ListDesktops` to check. Desktops are numbered across all displays in Mission Control order, so the second display's first desktop may be "Desktop 4":

```
Desktop 1: Built-in Retina Display desktop 1, shortcut on  (showing)
Desktop 2: Built-in Retina Display desktop 2, shortcut on
Desktop 3: Built-in Retina Display desktop 3, shortcut on
Desktop 4: Pavilion 27q (2) desktop 1, shortcut on  (showing)
```

Limits:

- Moving a window to another desktop on the same display needs a second display to park it on. With only the laptop screen, those windows are listed instead.
- Only the first 16 desktops have shortcuts.
- Full screen windows are not moved, since each one is its own desktop.

### yabai

[yabai](https://github.com/koekeishiya/yabai) with its scripting addition moves windows without switching desktops on screen. It requires partially disabling System Integrity Protection; follow yabai's own instructions. The helper finds `yabai` in `/opt/homebrew/bin` or `/usr/local/bin` and uses it automatically, before `--move-desktops`.

### Why not Apple Shortcuts?

The Shortcuts app's window actions (Find Windows, Move Window, Resize Window, Bring to Front) only place windows on the current desktop. None of them can target a desktop. Holding a window's title bar while switching desktops, the trick some window managers use, does not work with simulated mouse input on macOS 26.

Missing desktops are not created. If a profile uses desktop 4 on a display that has only 3, those windows are reported instead.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `WINDOW_LAYOUTS_DIR` | `~/.window_layouts` | Where profiles are stored. Set it in `bash_profile` before `RefreshScripts`, for example to a synced folder. |

## Files

| File | Purpose |
| --- | --- |
| `WindowLayouts.sh` | The shell commands. |
| `WindowLayoutHelper.swift` | Reads and moves windows through the Accessibility API. |
| `~/.cache/window_layouts/WindowLayoutHelper` | Compiled helper (safe to delete; it is rebuilt). |
| `~/.window_layouts/<name>.json` | Saved profiles. |

## Troubleshooting

- **"Accessibility access is missing"**: enable your terminal app under Privacy & Security › Accessibility, then quit and reopen it.
- **"Failed to compile"**: the helper tries the default SDK, then each installed SDK newest first, because a Command Line Tools update can ship an SDK newer than the compiler. Reinstalling the tools usually fixes it: `xcode-select --install`.
- **`--move-desktops` says "no shortcut for Desktop N"**: turn on that "Switch to Desktop" shortcut (see [Moving windows between desktops](#moving-windows-between-desktops)) and check with `ListDesktops`. `WindowLayoutHelper switch N` tests one shortcut on its own.
- **A window lands on the wrong window of the same app**: give the windows distinct titles, or re-save once they are open the way you want.
- **Profiles contain window titles**, which can include document names or chat names. They are stored only on your Mac.
