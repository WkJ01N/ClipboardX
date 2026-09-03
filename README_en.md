# ClipboardX

A native, local-first clipboard manager for macOS 15 and later, built with SwiftUI, SwiftData, and AppKit.

[简体中文](./README.md) | English

## Features

- Capture, search, and preview text, common image formats, and multi-file clipboard entries.
- Filter by content type or source app, with source and missing-file indicators.
- Open via a global shortcut, modifier double-tap, or key long-press; navigate by keyboard and Quick Look.
- Press `Enter` to paste or `Shift+Enter` to paste plain text. Without Accessibility access, ClipboardX safely falls back to copy-only.
- Sensitive text is encrypted at rest using AES-GCM with a Keychain-managed key and expires according to your retention setting.
- Image payloads live beside the database in `Payloads`, keeping history queries lightweight.
- Standard JSON backups exclude sensitive entries; complete backups use a password, PBKDF2-HMAC-SHA256, and AES-GCM.
- Versioned data migration creates a recovery snapshot before upgrading. Storage moves are copied and verified on restart.

## Install

Download `ClipboardX.pkg` from [Releases](https://github.com/WkJ01N/ClipboardX/releases) and run the installer. It installs ClipboardX at `/Applications/ClipboardX.app`. The ZIP is a portable fallback and its app must be moved to Applications manually.

The package is not signed with Developer ID or notarized. If macOS cannot verify it, Control-click the package and choose Open, or use **System Settings → Privacy & Security → Open Anyway**.

Do not disable Gatekeeper globally. ClipboardX does not require the “Allow apps from anywhere” system policy.

Automatic paste, caret positioning, and typewriter mode require Accessibility permission. Global long-press and modifier double-tap shortcuts may require Input Monitoring. ClipboardX shows permission status and links in Settings. If permission remains unavailable after an update despite the toggle being enabled, remove ClipboardX from the permission list and add `/Applications/ClipboardX.app` again.

## Development

```bash
xcodebuild test -project ClipboardX.xcodeproj -scheme ClipboardX -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
```

The deployment target is macOS 15. ClipboardX uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

## License

ClipboardX is available under the [MIT License](./LICENSE). Deck was used only as product inspiration; no restricted Deck source is included.
