# ClipboardX 2.1 验收清单

## 自动验证

```bash
xcodebuild test -project ClipboardX.xcodeproj -scheme ClipboardX -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
xcodebuild build -project ClipboardX.xcodeproj -scheme ClipboardX -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

CI 在 macOS 15 上执行同样的测试与 Release 构建。

## 手工回归矩阵

在 TextEdit、Safari/Chrome、Xcode 和 Finder 中分别验证：

- 普通文本、敏感文本、PNG/JPEG/GIF、单文件和多文件复制。
- Enter 粘贴、Shift+Enter/右键纯文本粘贴，以及权限关闭时仅复制并显示提示。
- 搜索文本，按内容类型和来源应用筛选，收藏、固定、Quick Look、网格/列表模式。
- 菜单栏、全局快捷键、双击/长按唤出、打字机模式。
- 单显示器与多显示器、全屏窗口、不同 Space。
- 辅助功能与输入监听权限分别开启、关闭。
- v1 JSON 导入、v2 普通备份、v2 加密备份、错误密码与损坏媒体。

## 数据与性能

- 用真实 v1 数据库副本升级，确认历史、收藏、固定和时间戳不丢失。
- 模拟迁移中断和不可写目标目录，确认原数据库及恢复快照仍可用。
- 导入 500 条记录与大图后，确认列表滚动不加载原图、后台复制不阻塞输入。
- 删除、过期或覆盖导入后，确认数据库记录与 `Payloads/` 文件同时清理；启动维护后无孤立文件。
