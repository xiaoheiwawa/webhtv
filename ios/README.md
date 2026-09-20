# WebHomeTV iOS 深度移植计划

本目录是 `webhtv`（Android 原生）到 iOS 原生（Swift）的深度移植。目标是让 GitHub Actions 直接产出**未签名 IPA**，
同时逐步把 CatVod/Spider 能力搬到 iOS。

## 目标形态

- 原生 Swift (UIKit) 应用，不含 Flutter。
- 用苹果 `JavaScriptCore` 运行现有的 `quickjs/src/main/assets/js/lib` 资产（已复制到 `Resources/JS/lib`）。
- CI：push / 手动触发 → `macos-latest` → `xcodegen generate` → `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → 打包 `Payload/WebHomeTV-...-unsigned.ipa` 上传。
- 单元测试不绑定具体机型：CI 用 `xcrun simctl list devices available` 动态选一个可用模拟器（优先 iPhone），镜像换 Xcode 也不会因 `iPhone 15` 之类被移除而报错。

## 当前状态

- [x] iOS 工程骨架（`project.yml` + XcodeGen 生成）
- [x] JS Spider 引擎（`SpiderEngine` + `ScriptLoader` + `ESModuleTransformer`）
- [x] 原生桥 `GlobalBridge.swift`（`native.*` + `req/http/console/setTimeout`）
- [x] 配置模型 `SiteConfig.swift` + 持久化 `ConfigStore.swift`（多配置、depot `urls` 递归、重启恢复）
- [x] WebHome 桥 `FongmiBridge.swift`（`window.fongmi`：`net.*/site.*/config.*/cache.*/player.*/pan.check/navigation.*`）
- [x] 首页/站点列表 + WKWebView WebHome 渲染
- [x] 本地 HTTP 代理 `LocalHTTPProxy.swift`（`/webResource?url=` 转发 + CORS + Range）
- [x] 播放器 `PlayerManager.swift` + `VideoViewController.swift`（AVPlayer）
- [x] 播放控制：play/pause/seek/±15s/prev/next/replay/loop
- [x] 播放细节：倍速循环(Rate)、音轨/字幕切换、画中画(PiP)、截图、AirPlay、屏幕遥控面板
- [x] 单元测试（transformer/loader/site/playback/config/proxy 地址）
- [x] `.github/workflows/ios.yml` 产出未签名 IPA（含模拟器测试）
- [ ] 本地 proxy `/proxy` 接入 Spider 流（阶段二引擎，尚未接到代理路由）
- [ ] 遥控器实体键映射（iOS 无 D-pad，用屏幕面板替代，已做）
- [ ] 网盘驱动检测（`pan.check` 目前为骨架，未接真实检测服务）
- [ ] 字幕外挂、倍速持久记忆、重复列表播放

## 移植对照（Android → iOS）

| Android | iOS |
| --- | --- |
| `quickjs/.../QuickJSContext` | `JavaScriptCore.JSContext` |
| `quickjs/.../Global.java`/`Local.java` | `GlobalBridge.swift` |
| `okhttp3` | `URLSession`（`Network.swift`） |
| `SharedPreferences` (local 缓存) | `UserDefaults`/`ConfigStore` |
| `bean/Config + VodConfig` | `SiteConfig.swift` + `StoredConfig` |
| `HomeWebBridge` + `window.fongmi` | `FongmiBridge.swift` + `WKWebView` |
| 本地 HTTP Server (`/webResource`) | `LocalHTTPProxy.swift`（`NWListener`） |
| `PlayerManager` + ExoPlayer | `PlayerManager.swift` + `AVPlayer`/`AVPlayerViewController` |
| 倍速/音轨/字幕/投屏 | `Rate`/media selection/PiP/AirPlay `AVRoutePicker` |
| DLNA | AirPlay（系统级） |

## 里程碑

1. CI 出包闭环（push → 未签名 IPA）✔
2. JS Spider 引擎加载（transformer/loader/native 桥）✔
3. 配置导入 + 站点列表 + WebHome 首页 ✔
4. 本地代理 + AVPlayer 播放 + 控制 ✔
5. 播放细节：倍速/音轨/字幕/PiP/截图/AirPlay/屏幕遥控 ✔
6. Windows 增强：持久化 + `/webResource` stream + `pan.check`/`navigation` 骨架 ✔（网盘真实检测、`/proxy` 流接入待办）
7. 真机/侧载安装验证（未签名需 AltStore 等）——待你推 CI

## 使用方法（GitHub 自动出包）

1. 推分支到你的 GitHub 仓库。
2. `Actions` 选 **构建 iOS 未签名 IPA**，手动或 push 到 `ios/**` 触发。
3. 在运行页 `ios-ipa-unsigned` Artifact 下载 `WebHomeTV-ios-arm64-unsigned.ipa`。

### 本地生成工程（需 macOS + Xcode）
```bash
brew install xcodegen
cd ios
xcodegen generate
open WebHomeTV.xcodeproj
```
> 工程由 `project.yml` 生成，`WebHomeTV.xcodeproj` 不入库（见 `.gitignore`）。

### 关于未签名 IPA
- 未签名 IPA 无法从 App Store 直接安装，需侧载（AltStore / Sideloadly / TrollStore）或免费 Apple ID 签名真机安装。
- 正式分发再接入付费 Developer 证书与 GitHub Secrets。
