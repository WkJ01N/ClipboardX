# ClipboardX

A geek-tier, fully native clipboard manager for macOS. Built with SwiftData and SwiftUI. 100% local, secure, and incredibly powerful.

<a href="./README.md">简体中文</a> | English

### 🔒 Extreme Privacy & Security
- **Anti-Screen-Share Stealth**: When enabled, the ClipboardX window becomes completely invisible to screen recording apps (Zoom, Teams, OBS, etc.), preventing accidental leaks.
- **Sensitive Data Auto-Destruct**: Automatically detects API Keys, ID numbers, and Credit Cards via Regex. Marks them with a 🔒 and permanently deletes them after a custom short period (e.g., 1 minute).
- **URL Tracker Stripper**: Automatically purges tracking parameters (like `utm_*`, `vd_source`, `si`) from copied links. Supports deep extraction from mixed text and customizable Regex rules.
- **Global Pause**: Instantly halt all clipboard monitoring via the menu bar or a global shortcut.

### ⌨️ Hardcore Productivity
- **Typewriter Mode (Simulation Paste)**: A dedicated text-only panel that simulates physical hardware keystrokes using `CGEvent`. Perfect for bypassing strict "pasting disabled" websites and remote desktop environments.
- **Crypto Assistant**: Right-click to Encode/Decode text using Base64 or URL formats. Features a "Smart Decrypt" button to instantly restore obscured data.
- **Grid View & 2D Navigation**: Switch between the classic list and a new high-density Dual-Column Grid. The underlying keyboard engine has been rewritten so you can navigate flawlessly using Up/Down/Left/Right arrows.
- **Advanced Activation**: Summon the panel using standard shortcuts, **Double-Click Modifiers** (e.g., double-tap Option ⌥), or **Long-Press Activation**.

### 💾 Full Data Mastery
- **Favorites System**: Star your most used snippets. Favorited items are kept forever and are immune to the database's auto-cleanup cycle.
- **Import / Export**: Backup your entire clipboard history to a JSON file. Supports "Merge" and "Overwrite" import modes.
- **Custom Storage Path**: Move your `.store` database file anywhere you like (e.g., iCloud Drive) for cross-device syncing or deep customization.

## 📥 Download & Installation

Download the latest version from the [Releases](https://github.com/WkJ01N/ClipboardX/releases) page.

Since the author cannot afford an Apple Developer Program membership, the app is not code-signed. You will need to bypass macOS Gatekeeper:
1. Open **System Settings** -> **Privacy & Security**, scroll to the bottom, and allow apps downloaded from **Anywhere**.
2. **If you don't see the "Anywhere" option**, open **Terminal** and run:
   ```bash
   sudo spctl --master-disable
   ```
   Enter your password and check Settings again.
3. Unzip the downloaded file and drag `ClipboardX.app` into your **Applications** folder, then double-click to launch.

> **⚠️ IMPORTANT:**
> To use **"Typewriter Mode"** (keyboard simulation), you MUST go to System Settings -> Privacy & Security -> **Accessibility**, and check the box to allow ClipboardX to control your computer.

## 🕹 Shortcuts Guide

- **Summon ClipboardX**: Ctrl + V (Customizable, supports double-click/long-press)
- **Quick Paste**: Cmd + 1 ~ 9
- **Navigation**: Up / Down / Left / Right Arrows
- **Quick Look (Preview)**: Spacebar
- **Confirm Paste**: Enter
- **Switch Tabs (History/Favorites)**: Tab
- **Clear Unpinned Items**: Cmd + Delete -> Enter
- **Close Panel**: ESC

## 🛠 Tech Stack

- **UI Framework**: SwiftUI (Dark mode, fluent animations, modular components)
- **Database**: SwiftData (@Model & @Query, SQLite optimization)
- **Low-Level APIs**: AppKit (NSPanel routing, sharingType stealth), CGEvent (Hardware-level event simulation)
- **i18n**: String Catalog (Seamless EN/ZH-Hans switching)
- **Dependencies**: KeyboardShortcuts

## 📄 License

This project is open-sourced under the MIT License. Feel free to use, modify, and distribute. If ClipboardX boosted your productivity, consider giving it a ⭐️ Star!
