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
| `LoadWindowLayout <name> [--dry-run] [--launch]` | Moves and resizes windows to match a profile. |
| `ListWindowLayouts` | Lists profiles with window count, displays and save date. |
| `ShowWindowLayout <name>` | Shows a profile's windows grouped by display and desktop. |
| `DeleteWindowLayout <name>` | Permanently deletes a profile. |

### Load options

| Option | Effect |
| --- | --- |
| `--dry-run` | Prints where each window would go. Nothing moves. |
| `--launch` | Opens apps from the profile that are not running, waits for them, then places their windows. |

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
LoadWindowLayout work --launch
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
3. **Desktop.** If a window is on a different desktop than saved, it is moved there with yabai (see below), or listed at the end of the output.
4. **Placing.** The window is moved and resized. Its full screen and minimized state are restored.

Windows that are not open are reported as `missing`. Use `--launch` to open their apps first.

## Limitation: moving windows between desktops

Since macOS 14.5, Apple blocks other apps from moving windows between desktops. Every window is placed and sized correctly on the desktop it is on, but one sitting on the wrong desktop stays there and is listed so you can drag it over:

```
These windows are on a different desktop than saved. ...
  Slack - general (on desktop 1, saved on Built-in Retina Display, desktop 3)
```

To automate this step, install [yabai](https://github.com/koekeishiya/yabai) and its scripting addition. That requires partially disabling System Integrity Protection; follow yabai's own instructions. The helper finds `yabai` in `/opt/homebrew/bin` or `/usr/local/bin` and uses it automatically.

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
- **A window lands on the wrong window of the same app**: give the windows distinct titles, or re-save once they are open the way you want.
- **Profiles contain window titles**, which can include document names or chat names. They are stored only on your Mac.
