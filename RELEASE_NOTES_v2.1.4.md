# ClipboardX v2.1.4 - 菜单栏图标独立控制

## 修复

- 修复在 macOS“系统设置 → 菜单栏”中关闭 ChatGPT 等其他应用的图标后，ClipboardX 图标也可能消失的问题。菜单栏项目现在使用 ClipboardX 专属的稳定标识，避免复用系统中的旧关联。
- 菜单栏弹窗继续提供剪贴板历史、内容预览、设置及暂停监听入口；关闭弹窗时释放临时状态和事件监听。
- 保留应用内的图标显示开关及图标选择，并尊重系统对 ClipboardX 图标本身的显示设置。

## 安装

- 更新前请退出正在运行的 ClipboardX。
- 推荐下载 `ClipboardX.pkg`，安装至 `/Applications/ClipboardX.app`。
- `ClipboardX.zip` 为备用包，解压后将应用放入“应用程序”。
- 可使用 `SHA256SUMS.txt` 校验下载文件。

## 版本信息

- 应用版本：**2.1.4**
- 构建版本：**216**
- 最低系统版本：macOS 15

应用沿用 Apple Development 签名；PKG 外层未签名，应用和安装包尚未经过 Apple 公证。如 macOS 阻止首次打开，可在“系统设置 → 隐私与安全性”中选择“仍要打开”。
