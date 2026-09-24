# WiFi Priority｜中文说明

**直接下载：[WiFi Priority 0.9.4 Apple Silicon 安装包（DMG）](https://github.com/xiaohardy/WiFiPriority/releases/download/v0.9.4/WiFiPriority-0.9.4-build16-preview-arm64.dmg)** · [版本说明](https://github.com/xiaohardy/WiFiPriority/releases/tag/v0.9.4)

这是未经 Apple 公证的预览版；如果首次打开被拦截，请看下面的[安装步骤](#安装)和[系统提示处理方法](#首次打开时的-macos-安全提示)。

[English](README.md)

告诉它所有wifi的重要性，排好序，然后感受它吧

![WiFi Priority 中文设置窗口，显示三个示例网络](docs/images/settings-preview-zh.png)

*图中都是虚构网络，放心，你家 Wi-Fi 没上镜。*

## 安装

1. 从 [v0.9.4 预览版](https://github.com/xiaohardy/WiFiPriority/releases/tag/v0.9.4)下载适用于 Apple Silicon 的 DMG。
2. 打开 DMG，把 **WiFi Priority.app** 拖进 **Applications**。
3. 从“应用程序”打开软件；它会待在屏幕顶部的菜单栏。

![安装镜像中只有 WiFi Priority 和 Applications](docs/images/installer.png)

### 首次打开时的 macOS 安全提示

这个预览版使用本地证书签名，**尚未经过 Apple 公证**。从 GitHub 下载后，macOS 可能提示“Apple 无法检查 App 是否包含恶意软件”或“无法验证开发者”。只有在确认 DMG 来自[本项目的发布页](https://github.com/xiaohardy/WiFiPriority/releases/tag/v0.9.4)，并且你信任它时，才继续：

1. 把软件拖进“应用程序”后，尝试打开一次。如果出现警告，选择“完成”（如有）。
2. 打开“系统设置 → 隐私与安全性”，向下找到“安全性”，点“仍要打开”。
3. 系统再次询问时，点“打开”。

macOS 会在这台 Mac 上记住你对这个 App 的选择。详细步骤见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。如果提示 **“App 已损坏”**或**“将损坏您的电脑”**，先别打开，请在 [Issues](https://github.com/xiaohardy/WiFiPriority/issues) 告诉我们。不需要关闭整个系统的安全检查。

目前只在 Apple Silicon、macOS 27 上检查过；最低系统目标为 macOS 13，其他版本和 Intel Mac 尚未实测。

## 排好顺序，开始使用

1. 先在 macOS 的 Wi-Fi 设置中连接并保存要用的网络。软件负责排队，不负责凭空变出密码。
2. 在应用中加入这些网络，把首选放最上面，保存顺序。macOS 询问定位权限时请允许，这是读取当前和附近 Wi-Fi 名称所需。
3. 点击“启用自动切换”。macOS 可能对列表中的加密网络分别询问钥匙串权限；Wi-Fi 密码改过后，可点“更新已保存凭据…”。

应用只读取列表内网络的凭据，获授权的副本保存在你的登录钥匙串，不写入设置或日志。日志会记录 Wi-Fi 名称；分享故障信息前，记得把名称遮一下。

菜单栏的星星按优先顺序站位，亮一点的那颗对应当前网络；暂停后图标会变灰，算是下班了。你也可以设置暂停／开启快捷键，或者干脆不设。手动测试时，先暂停，再选中网络点击“在系统 Wi-Fi 中测试”，由 macOS 完成连接。

iPhone 即时热点有时只在系统 Wi-Fi 里出现，普通扫描找不到它。遇到这种情况可以在系统里手动连接；应用只有在热点作为可发现的 Wi-Fi 网络出现时，才能让它参与自动切换。

## 反馈与许可

发现问题或有改进建议，请到 [GitHub Issues](https://github.com/xiaohardy/WiFiPriority/issues)。源码按 [MIT 许可证](LICENSE)发布；构建方法见 [英文说明](README.md#build-from-source)。
