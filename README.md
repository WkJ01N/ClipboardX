# ClipboardX

面向 macOS 15 及更高版本的原生、本地优先剪贴板管理器。使用 SwiftUI、SwiftData 与 AppKit 构建。

简体中文 | [English](./README_en.md)

## 功能

- 记录、搜索和预览文本、常见图片格式及多文件复制记录。
- 按内容类型和来源应用筛选，显示来源应用与文件缺失状态。
- 全局快捷键、双击修饰键或长按按键唤出；支持方向键、`Cmd+1...9` 和 Quick Look。
- `Enter` 自动粘贴，`Shift+Enter` 粘贴为纯文本；没有辅助功能权限时安全降级为仅复制。
- 敏感文本以 Keychain 管理的 AES-GCM 密钥加密保存，并按设置自动删除。
- 图片负载存放在数据库旁的 `Payloads` 目录，避免历史查询加载完整图片。
- 普通 JSON 备份会排除敏感项；完整备份采用口令、PBKDF2-HMAC-SHA256 和 AES-GCM 加密。
- 数据模型版本化迁移，迁移前自动建立恢复快照；存储位置变更在重启时安全完成。

## 安装

从 [Releases](https://github.com/WkJ01N/ClipboardX/releases) 下载 `ClipboardX.pkg` 并完成安装，应用会被安装到 `/Applications/ClipboardX.app`。ZIP 仅作为便携备用包，使用时必须先将其中的应用拖入“应用程序”。

当前安装包尚未签署 Developer ID 或经过 Apple 公证。如果 macOS 提示无法验证开发者，请右键安装包选择“打开”，或前往“系统设置 → 隐私与安全性”点击“仍要打开”。

不要全局关闭 Gatekeeper。ClipboardX 不要求修改系统的“允许任何来源”策略。

自动粘贴、跟随输入光标和打字机模式需要“辅助功能”权限；长按/双击全局按键可能需要“输入监控”权限。应用会在设置中显示权限状态和对应入口。更新应用后如果系统开关已经开启但 ClipboardX 仍显示未授权，请在权限列表中移除 ClipboardX，再从 `/Applications` 重新添加。

## 开发

```bash
xcodebuild test -project ClipboardX.xcodeproj -scheme ClipboardX -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
```

项目最低部署版本为 macOS 15，依赖 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)。

## 许可证

ClipboardX 使用 [MIT License](./LICENSE)。Deck 仅作为产品方向参考，本项目不包含 Deck 的受限许可代码。
