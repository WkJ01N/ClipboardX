# ClipboardX

为 macOS 打造的原生剪贴板管理软件。基于 SwiftData 和 SwiftUI 构建，纯本地运行。

简体中文 | <a href="./README_en.md">English</a>

## 核心特性

- 支持 macOS 状态栏。
- 全局快捷键唤出，Cmd + 1 到 9 上屏，方向键导览。
- 支持记录、预览并粘贴纯文本、图片与文件。
- 空格键快速预览
- 常用记录置顶
- 本地运行，无任何数据上传
- 功能不多，但大多数都可以自定义

## 下载与安装

下载见 [Release](https://github.com/WkJ01N/ClipboardX/releases) 页面
由于主播贫困潦倒，买不起开发者账号，所以需要打开允许任何来源软件才能使用
1. 打开设置，找到“*隐私与安全性*”，翻到最底部，将“*允许以下来源的应用程序*”一项改为“***任何来源***”
2. 若你没有该选项，请打开**终端**，输入以下代码：

   ```Terminal
   sudo spctl --master-disable
按照提示输入密码之后再次打开设置就可以看到“任何来源”选项了

## 快捷键指南

- 唤出 ClipboardX：Ctrl + V (可在偏好设置中自定义)
- 快速粘贴：Cmd + 1 ~ 9
- 列表上下导览：上 / 下 方向键
- 快速预览：空格键
- 确认粘贴选定项：回车键
- 一键清空未固定项：Cmd + 删除键 -> 回车
- 关闭悬浮面板：ESC

## 技术架构

UI 框架: SwiftUI (高度组件化拆分)
数据持久化: SwiftData (@Model & @Query)
系统底层控制: AppKit (NSPanel 焦点路由拦截), CGEvent (硬件级键盘事件模拟)
开源依赖: KeyboardShortcuts

## 许可证

本项目基于 MIT License 协议开源。你可以自由地使用、修改和分发。
