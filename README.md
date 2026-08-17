# NeteaseGlass

一个面向 iOS 26 的简洁网易云音乐下载器，使用 SwiftUI 和原生 Liquid Glass 风格。

## 功能

- 网易云歌曲搜索、试听和真实下载权限检查
- 网易云歌单链接解析、歌曲列表和批量操作
- 网易云用户搜索、公开歌单浏览
- 二维码登录、登录状态持久化和账号歌单
- 可暂停、继续、重试和删除的下载队列
- 可展开和收起的播放控制条、播放进度、时间与剩余秒数
- 下载到 `Documents/Music/`，默认写入 MP3 ID3 元数据和封面
- GitHub Actions 在 macOS Runner 上构建未签名 IPA

## 本地打开

使用 Xcode 26 或更新版本打开 `NeteaseGlass.xcodeproj`，运行目标选择 iOS 26 模拟器或真机。

本项目按网易云请求协议调用搜索、歌单、账号和播放地址接口。接口仍可能受网易云风控、地区、版权和登录状态影响；下载按钮只在歌曲下载接口实际返回可用 URL 时开始任务。

## 构建未签名 IPA

Actions 工作流位于 `.github/workflows/build.yml`。它使用 macOS Runner，关闭 Code Signing，导出 `NeteaseGlass-unsigned.ipa` 并上传 Artifact。

## 版本

- Marketing Version: `2.4`
- Build Number: `17`

## 版本规则

- 每发布一个新版本，在现有版本号基础上加 `0.1`（例如 `1.9 → 2.0 → 2.1`），同时构建号（Build Number）加 `1`。
- 修改位置：`NeteaseGlass.xcodeproj/project.pbxproj` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，并同步更新本文件。
