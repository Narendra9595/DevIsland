<div align="center">

# DevIsland

**The notch app for developers.**

Turn your MacBook's notch into a live island for Claude Code, Codex, music, calls, files and your clipboard.
Native Swift, local-first, no account, no tracking.

![macOS](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![Apple silicon + Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

[**Download the latest DMG**](https://github.com/Narendra9595/DevIsland/releases/latest)

</div>

---

## What it does

Hover the notch and it opens into a small, glassy island. When something is happening (Claude is working, a song is playing, you're on a call), it shows beside the camera on its own.

### For developers
- **Claude Code, live.** What Claude is doing step by step ("Editing App.swift", "Running tests"), "Step 2 of 5" for plans, turn time, project and branch. The notch lights up when Claude **needs you**.
- **Plan limits.** Your Claude 5-hour and weekly limits, at a glance.
- **Ask Claude or Codex** from the notch in a small chat, using the sign-in you already have. No API keys. Read-only: it can't touch your files.
- **Codex.** Know the moment a turn finishes.

### Media
- **Now Playing** for Apple Music, Spotify and the Apple TV app: album art, a seek bar, controls, playlists and Apple Music search.
- **YouTube and streaming in your browser** (Chrome, Safari, Arc, Brave, Edge): YouTube, YouTube Music, Netflix, Prime Video, JioHotstar and more, with no extension needed.
- **Floating player** you can put anywhere on your desktop.

### Everyday tools
- **Calls and mic.** A green call timer with the caller's name, mute and leave buttons; an orange mic when an app records (like Apple's privacy dot).
- **Clipboard history** (⌃⌥V): text, links, code, colors and images; search and paste back. Off by default, kept in memory only.
- **File shelf.** Drop files on the notch; drag out, copy path, open in Terminal, AirDrop.
- **Notes, Focus timer, Keep Awake, Camera mirror.**
- **Volume and brightness HUD** at the notch (it can replace macOS's popup).
- **Downloads, battery and network** as live activities.

### Made to feel native
- Notch style, or a **floating iPhone-style island** on Macs without a notch and on external displays.
- Gestures: hover or click to open, two-finger swipe down/up to open/close, swipe left/right between pages.
- Hides itself in full screen; comes back when you point at the top.
- Battery-friendly: looping animations run in macOS's renderer, and stop in Low Power Mode. The dashboard shows exactly how much energy DevIsland uses.

---

## Download and install

1. Download **`DevIsland-x.y.z.dmg`** from the [latest release](https://github.com/Narendra9595/DevIsland/releases/latest).
2. Open the DMG and drag **DevIsland** into **Applications**.
3. Open DevIsland from Applications.

### First launch ("Apple can't check it for malicious software")
DevIsland isn't notarized by Apple yet, so macOS asks you to confirm the first time:

- **macOS 15 and later:** open DevIsland once, click **Done**, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to DevIsland.
- **macOS 14 and earlier:** right-click DevIsland in Applications → **Open** → **Open**.

<details>
<summary>Or with one Terminal command</summary>

```sh
xattr -dr com.apple.quarantine /Applications/DevIsland.app
```
</details>

After that it opens normally. DevIsland lives in the menu bar and in the notch; there's no Dock icon unless a window is open.

### Updates
DevIsland checks for a new version once a day (Settings → General → Updates). When one is out, a dot appears on the ⚙️ in the island and Settings → About shows **Download Update**. Download the new DMG and drag DevIsland into Applications, replacing the old one. Your settings and history stay.

> Using version 1.0.0? It doesn't have the update check yet, so download the latest release once by hand.

### Permissions (all optional, asked only when you use the feature)

| Permission | Used for |
|---|---|
| **Automation** (Music, Spotify, TV, browsers) | Song info, artwork and controls; the playing YouTube tab's title |
| **Accessibility** | Clipboard paste, hiding macOS's volume popup, call mute and caller names |
| **Camera** | Mirror (only while it's open; nothing is recorded) |
| **Downloads folder** | Download progress (off by default) |

---

## Getting started

1. **Connect Claude Code:** Dashboard → Agents → **Connect**. DevIsland adds a few small hooks to `~/.claude/settings.json` (with a backup first). New Claude Code sessions then show up in your notch.
2. **Explore:** Dashboard → **Features** lists everything DevIsland can do, with how to use it and a button to try it.
3. **Make it yours:** Settings → **Customize** for the highlight color, corner roundness and island style.

### Shortcuts and gestures

| | |
|---|---|
| Open the island | Hover the notch, click it, or swipe down with two fingers |
| Close it | Move away, swipe up, press **Esc**, or click outside |
| Switch pages | Two-finger swipe left/right, or the tabs at the bottom |
| Keep it open | **⌃⌥I** |
| Clipboard | **⌃⌥V** |

---

## Build from source

Requires macOS 15+ and Xcode 16+ (or the Swift 6 toolchain).

```sh
git clone https://github.com/Narendra9595/DevIsland.git
cd DevIsland
swift run                     # run a debug build
sh Scripts/build-app.sh       # build build/DevIsland.app
sh Scripts/make-dmg.sh        # build build/DevIsland-x.y.z.dmg
swift test                    # run the tests
```

How the Claude Code and Codex connections work is described in [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

---

## Privacy

- **Local-first.** No account, no analytics, no telemetry. History is stored only on your Mac (`~/Library/Application Support/DevIsland`).
- **Never reads your prompts, code or file contents.** From Claude Code it shows the step it's on, file names and the first line of its messages (you can turn messages off).
- **Network only for:** Apple Music catalog search and Ask (sent to Claude or Codex through your own sign-in), when you use them, plus a daily update check with GitHub that sends nothing about you (can be turned off).
- Clipboard history is opt-in, kept in memory and skips password-manager items. Calls are detected from which app uses the mic; audio is never read or recorded.

---

## FAQ

**Does it work on Macs without a notch?** Yes. It becomes a floating island at the top of the screen (Settings → Customize → Island style).

**Claude's plan limits don't show.** They come from Claude Code's status line, which runs in the terminal version of Claude Code. Send one message in a terminal session and they appear.

**YouTube controls start Apple Music instead.** Media keys go to whichever app played most recently. Play the video once in the browser and the controls follow it.

**How much battery does it use?** Dashboard → Home → Energy shows DevIsland's own usage, measured by macOS. It's typically a fraction of a percent per day.

---

## Contributing

Issues and pull requests are welcome. Please keep it native (SwiftUI + AppKit, no Electron), local-first, and battery-friendly.

## License

[MIT](LICENSE)

DevIsland is an independent project and isn't affiliated with Apple, Anthropic or OpenAI. Claude, Claude Code, Codex, ChatGPT and other names are trademarks of their owners.
