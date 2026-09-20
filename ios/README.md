# WebHomeTV iOS 深度移植计划

本目录是 `webhtv`（Android 原生）到 iOS 原生（Swift）的深度移植。目标是让 GitHub Actions 直接产出**未签名 IPA**，
同时逐步把 CatVod/Spider 能力搬到 iOS。

## 目标形态

- 原生 Swift (UIKit) 应用，不含 Flutter。
- 用苹果 `JavaScriptCore` 运行现有的 `quickjs/src/main/assets/js/lib` 资产（已复制到 `Resources/JS/lib`）。
- CI：push / 手动触发 → `macos-latest` → `xcodegen generate` → `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → 打包 `Payload/WebHomeTV-...-unsigned.ipa` 上传。

## 当前状态

- [x] iOS 工程骨架（`project.yml` + XcodeGen 生成）
- [x] 入口 `AppDelegate.swift` + 首页占位 `HomeViewController.swift`
- [x] JS 运行时封装 `SpiderEngine.swift`（JSCore）与原生桥 `GlobalBridge.swift`
- [x] 原生工具占位：`Network`、`CryptoUtil`、`SimplifiedConverter`
- [x] `.github/workflows/ios.yml` 产出未签名 IPA
- [ ] 本地 HTTP 代理（对应 `catvod Proxy`/本地 Server）
- [ ] JS ES-module 加载器（`spider.js` 的 `import * as spider from '%s'`）
- [ ] 配置读取（站点、HomePage、CSP API 地址解析）
- [ ] WebHome `WKWebView` + `window.fongmi` 桥
- [ ] 播放器（AVPlayer）、遥控器按键、投屏（AirPlay）
- [ ] 网盘检测 / Nostr / TMDB 等增强能力

## 移植对照（Android → iOS）

| Android | iOS |
| --- | --- |
| `quickjs/.../QuickJSContext` | `JavaScriptCore.JSContext`（原生） |
| `quickjs/.../Global.java` / `Local.java` | `GlobalBridge.swift` |
| `okhttp3` | `URLSession`（`Network.swift`） |
| `SharedPreferences` (local 缓存) | 内存 `UserDefaults`/本地存储 |
| 本地 HTTP Server (Proxy/Server) | 待移植（URLSession/TCPServer 或嵌入式 HTTP） |
| WebView + `window.fongmi` | `WKWebView` + WKScriptMessageHandler |
| ExoPlayer | `AVPlayer` / `AVPlayerViewController` |
| DLNA | AirPlay（系统级） |

## 里程碑（后续迭代依次推进）

1. **CI 出包闭环**（已完成工程 + 工作流；push 后即产 IPA）
2. JS Spider 引擎完整加载（`csp_*` 源可跑 homepage/search/detail/play）
3. 配置导入与站点列表、WebHome 首页接管
4. 点播/直播播放器 + 遥控器按键
5. 网盘检测 / Nostr / TMDB / 投屏增强
6. 真机/侧载安装验证（未签名需 AltStore 等）

## 说明

- 我在 Windows 环境无法本地编译 Xcode 工程，工程与 CI 由 GitHub `macos-latest` 编译真实验证。
- 未签名 IPA 无法通过 App Store 安装，需侧载（如 AltStore / Sideloadly），或真机免费 Developer 签名。
## 使用方法（GitHub 自动出包）

1. 把分支推送到你的 GitHub 仓库。
2. 仓库 `Actions` 页选择 **构建 iOS 未签名 IPA**，可 `Run workflow` 手动触发；push 到 `ios/**` 或 `.github/workflows/ios.yml` 也会自动触发。
3. 构建完成后在该次运行的 `ios-ipa-unsigned` Artifact 下载 `WebHomeTV-ios-arm64-unsigned.ipa`。

### 本地生成工程（需要 macOS + Xcode）
```bash
brew install xcodegen
cd ios
xcodegen generate
open WebHomeTV.xcodeproj
```
> 工程由 `project.yml` 生成，`WebHomeTV.xcodeproj` 不入库（已在 `.gitignore`）。

### 关于未签名 IPA
- 未签名 IPA 无法从 App Store 直接安装，需要侧载工具（如 AltStore / Sideloadly / TrollStore），或用免 费 Apple ID 签名后真机安装。
- 如需正式分发，再接入付费 Developer 证书与 GitHub Secrets。
