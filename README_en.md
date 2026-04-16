# ClipboardX

A native clipboard management application designed for macOS. Built with SwiftData and SwiftUI, runs entirely locally.

<a href="./README.md">简体中文</a> | English

## Core Features

* Supports the macOS status bar.
* Summoned via global hotkeys; paste with Cmd + 1 to 9, and navigate with arrow keys.
* Supports recording, previewing, and pasting plain text, images, and files.
* Quick preview with the Spacebar
* Pin frequently used records to the top
* Runs locally with no data uploaded whatsoever
* Limited but highly customizable features

## Download & Installation

Download: See the [Releases](https://github.com/WkJ01N/ClipboardX/releases) page.

Install: You they need to enable the permission to allow software from any source in order to use it:
1. Open Settings, find "*Privacy & Security*", scroll to the bottom, and change the option "*Allow apps from*" to "***Any source***"
- If you do not have this option, please open **Terminal** and enter the following code:

   ```Terminal
   sudo spctl --master-disable
- After entering your password as prompted, you can see the "Any Source" option when you open the settings again
2. Unzip the downloaded archive(.zip) to a local directory, then drag the ClipboardX.app file into the "Applications" folder, and you can open the software.

## Shortcut Guide

* Summon ClipboardX: Ctrl + V (customizable in Preferences)
* Quick direct paste: Cmd + 1 to 9
* Navigate up and down the list (Select): Up / Down arrow keys
* Full-size quick preview: Spacebar
* Confirm pasting the selected item: Enter
* Clear all unpinned items: Cmd + Delete -> Enter
* Close the floating panel: ESC
## Technical Architecture
UI Framework: SwiftUI (Highly modular component splitting)
Data Persistence: SwiftData (@Model & @Query)
System Low-Level Control: AppKit (NSPanel focus routing interception), CGEvent (Hardware-level keyboard event simulation)
Open-Source Dependencies: KeyboardShortcuts
## License
This project is open-source under the MIT License. You are free to use, modify, and distribute it.
