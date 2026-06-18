# snail-lock

Fake lock screen for macOS. Runs as a tiny background app with a 🐌 in the menu bar; hit ⌥L (or the menu, or the in-app button) and a fullscreen overlay covers every monitor with a bouncing-emoji background and a hidden password prompt. The OS session stays unlocked underneath, so Slack/Zoom/syncs/downloads keep running while you're "locked".

Single-file SwiftUI + AppKit app. No dependencies beyond the Xcode Command Line Tools.

## Install

### Clone & run (builds from source)

```sh
git clone https://github.com/justmeben/snail-lock.git
cd snail-lock
./install.sh
```

`install.sh` builds the app from source (needs the Xcode Command Line Tools — run `xcode-select --install` if you don't have them), prompts for a password and on-screen message (Enter for defaults), installs the `.app` to `/Applications`, writes `~/.snail_lock.conf`, and launches it. On launch you'll see the settings window plus a 🐌 in the menu bar.

### One-liner (prebuilt, no Xcode)

If a release has been published, you can skip the build:

```sh
curl -fsSL https://raw.githubusercontent.com/justmeben/snail-lock/main/remote-install.sh | bash
```

This downloads the prebuilt app from the latest GitHub release, strips quarantine, installs, configures, and launches it.

## Using it

- **🐌 in the menu bar** — single-click drops down: "Lock now", "Open settings…", "Quit".
- **⌥L** (default) — global hotkey to lock from anywhere. Configurable in settings.
- **"Lock now" button** in the settings window — locks immediately.

When locked: click the big 🐌 (or whatever `unlock_icon` is set to) to reveal the password field. Type the password and press Enter; the overlay disappears and the app keeps running so the next hotkey press works.

## Settings UI

Opening the app (or selecting "Open settings…" from the menu bar) shows a native window with fields for every config key:

- Password
- Message (the big text shown to bystanders)
- Unlock icon (the clickable emoji at the bottom)
- Background icons (comma-separated; repeats act as spawn-weight)
- Lock hotkey (click the recorder → press the combo)
- "Lock now" button

Changes are written back to `~/.snail_lock.conf` automatically (debounced ~250ms). Hand-edits to the config file are preserved when the UI saves: comments and unknown keys stay put.

## Build from source

```sh
swiftc lock.swift -o snail-lock          # compile
./build-app.sh                            # build Snail Lock.app + SnailLock.zip
open "Snail Lock.app"                     # or double-click in Finder
```

`build-app.sh` produces a universal (arm64 + x86_64) binary, ad-hoc signs the bundle, and packages `SnailLock.zip`.

## Publish a release

Attach the generated `SnailLock.zip` to a GitHub release. Once it's published:

- `remote-install.sh` (the curl one-liner above) downloads it automatically.
- Anyone can also grab `SnailLock.zip` straight from the Releases page, unzip it, and double-click `Install.command` — same quarantine-strip + install + config + launch flow, no terminal needed.

## Config file (`~/.snail_lock.conf`)

```
password=slug
message=BRB — DO NOT TOUCH
unlock_icon=🐌
icon_set=🐌, 🐌, 🐌, 🐚, 🐛, 🌿, 🍃, 🌱, 🍄, 🪱
lock_hotkey=option+l
```

`lock_hotkey` accepts any combo of `cmd` / `shift` / `option` / `control` + one key (letter, digit, `space`, `return`, `escape`, `tab`, `f1`–`f12`). Joined by `+`. Examples: `option+l`, `cmd+shift+l`, `control+f12`.

## Escape hatch

If anything goes wrong and you're stuck behind the lock — open a remote shell (ssh from another device, or a saved tmux session) and:

```sh
pkill -x snail-lock
```

## How the "fake lock" works

- App runs with `.accessory` activation policy (no Dock icon, no menu bar item until we add one).
- 🐌 menu bar icon via `NSStatusBar.system`.
- Lock overlay = borderless `NSWindow` per `NSScreen` at `.screenSaver` level with `.canJoinAllSpaces` — covers every display + every Space.
- While the overlay is up, `NSApp.presentationOptions` hides the Dock, menu bar, Apple menu, force-quit dialog, process switcher (Cmd-Tab), and Hide-App. So Cmd-Q / Cmd-Opt-Esc / Cmd-H / etc. are all blocked. When you unlock, those options are restored to what they were.
- Global hotkey via Carbon `RegisterEventHotKey` so it fires from any focused app (no Accessibility / Input Monitoring permission needed).
- The OS session is **not** locked, so apps that pause on screen-lock (Zoom, Slack-do-not-disturb) keep running normally.

## License

MIT — see [LICENSE](LICENSE).

## Files

- `lock.swift` — the app (single file)
- `install.sh` — clone-and-run installer; builds from source, configures, launches
- `remote-install.sh` — curl one-liner installer; downloads the prebuilt app from the latest GitHub release
- `build-app.sh` — builds the universal `.app` bundle, signs ad-hoc, packages `SnailLock.zip`
- `snail_lock.conf.example` — config template
