# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Use the Gradle wrapper through bash from the repo root.

```bash
# Clean all Gradle outputs
bash gradlew clean

# Common release APK builds; outputs are also copied to Release/apk by the root build.gradle
bash gradlew :app:assembleMobileArm64_v8aRelease
bash gradlew :app:assembleMobileArmeabi_v7aRelease
bash gradlew :app:assembleLeanbackArm64_v8aRelease
bash gradlew :app:assembleLeanbackArmeabi_v7aRelease

# Build all modules/variants
bash gradlew build

# Lint all app variants, or one concrete variant
bash gradlew :app:lint
bash gradlew :app:lintMobileArm64_v8aRelease

# Unit tests. This repo currently has no src/test or src/androidTest tree, but these are the variant commands to use when tests are added.
bash gradlew test
bash gradlew :app:testMobileArm64_v8aDebugUnitTest --tests 'com.fongmi.android.tv.ExampleTest'

# Instrumented tests for a connected device/emulator when androidTest tests exist
bash gradlew :app:connectedMobileArm64_v8aDebugAndroidTest
```

Build environment notes from the repo:

- The README lists JDK 17, Android SDK, and the repo's `gradlew` as required. The Gradle files set Java source/target compatibility to `JavaVersion.VERSION_21`.
- `gradle/libs.versions.toml` currently sets `compileSdk = 37`, `targetSdk = 28`, and `minSdk = 24`.
- Release builds use signing values from `local.properties` (`storeFile`, `keyAlias`, `storePassword`) when present; otherwise they fall back to debug signing for local testing.
- The project depends on local artifacts in `app/libs/*.aar` and `third_party/maven`, including a pinned `androidx.media3:*:1.10.1-fongmi` build.

## High-level architecture

This is an Android Gradle project for WebHomeTV, a FongMi/CatVod-derived video app with custom WebHome pages, native WebView SDK support, Spider runtimes, local HTTP services, playback, DLNA, sync, and drive-link detection.

### Modules

- `:app` is the Android application (`com.fongmi.android.tv`). It owns UI, config loading, playback, WebHome integration, local HTTP endpoints, database, settings, sync, and release APK flavors.
- `:catvod` is the shared CatVod abstraction/network layer used by the app and Spider runtimes.
- `:quickjs` embeds the JavaScript Spider runtime and includes JS helper libraries under `quickjs/src/main/assets/js/lib`.
- `:chaquo` embeds the Python Spider runtime with Chaquopy and installs `chaquo/requirements.txt`.

### Build and variants

The app has two flavor dimensions:

- `mode`: `mobile` and `leanback`.
- `abi`: `arm64_v8a` and `armeabi_v7a`.

Release APK filenames are rewritten to names like `mobile-arm64_v8a.apk`, and root `build.gradle` copies release APKs from `app/build/outputs/apk/**/release` into `Release/apk` after assemble tasks.

Dependencies are centralized in `gradle/libs.versions.toml`. `settings.gradle` intentionally resolves dependencies from the bundled `third_party/maven`, Maven Central, Google, `app/libs`, and JitPack; project repositories are disabled via `RepositoriesMode.FAIL_ON_PROJECT_REPOS`.

### App runtime structure

- `app/src/main/java/com/fongmi/android/tv/App.java` is the application class, with startup registered through AndroidX Startup in `AndroidManifest.xml`.
- `PlaybackActivity` is the main playback UI activity; `PlaybackService` exposes Media3 media session/browser service integration and foreground playback.
- Room database classes live under `app/src/main/java/com/fongmi/android/tv/db`, with schema snapshots in `app/schemas`.
- EventBus annotations are processed with `eventBusIndex = com.fongmi.android.tv.event.EventIndex`; Room schemas are generated into `app/schemas`.

### Config, CSP, and Spider flow

- Config models and loaders are under `app/src/main/java/com/fongmi/android/tv/api`.
- `VodConfig`, `LiveConfig`, `RuleConfig`, and `WallConfig` extend the common config base and feed site/live/rule data into the app.
- `Site` includes WebHome-compatible homepage aliases: `homePage`, `home_page`, `webHome`, and `web_home`.
- `SiteApi` is the central Spider API facade; `JarLoader`, `JsLoader`, and `PyLoader` connect Java/JAR, QuickJS, and Chaquopy Spider implementations.
- Custom CSP/WebHome site injection is managed through `setting/CustomCspSetting.java`, `ui/dialog/CustomCspDialog.java`, and the management HTTP process.

### WebHome and native bridge

- WebHome pages are loaded through `web/HomeWebController.java`, which injects `window.fongmi` and `window.fm` via the `fongmiBridge` JavaScript interface and dispatches the `fmsdk` event when ready.
- `web/HomeWebBridge.java` implements native capabilities exposed to WebHome pages, including native HTTP requests, resource proxy URLs, playback, CSP VOD navigation, search, history, playback state/control, config/site/device data, cache, back/reload, and drive-link APIs.
- Header/cookie behavior for WebHome network/resource access is isolated in `web/HeaderPolicy.java` and `web/CookieBridge.java`.
- Demo WebHome pages are in `demo/`; `README.md` documents `demo/nostr.html` and `demo/check.html`, while this checkout also contains localized/variant demo HTML files.

### Local HTTP service

- `server/Server.java` starts the local NanoHTTPD instance; `server/Nano.java` registers request processors in order.
- Processors under `server/process` implement app-local endpoints, including action control, cache, debug logs (`/debug/logs`), drive detection (`/pan/check`), local file access, web management/sync, media state, parser/proxy behavior, and WebHome resource proxying (`/webResource`).
- `ManageService` keeps the management service alive for local/LAN management and sync workflows.

### Playback and media

- Playback orchestration lives under `player/`, centered on `PlayerManager`, `PlayerHelper`, `ParseJob`, `Source`, and the `engine` package.
- ExoPlayer/Media3 integration is under `player/exo` and `player/engine`; extractor-specific paths such as Push, TVBus, Thunder, JianPian, Force, Strm, Video, and YouTube are under `player/extractor`.
- `app/build.gradle` forces all `androidx.media3` dependencies to the bundled version from `libs.versions.toml` because the repo uses a custom Media3 build with MediaTitle and danmaku APIs.

## Documentation to consult

- `README.md` is the concise project overview, build guide, WebHome SDK summary, and demo description.
- `docs/应用完整开发文档.md` is the detailed reference for app config fields, Spider development, JS/Python runtimes, local HTTP APIs, WebHome SDK parameters/returns, transparent WebHome behavior, drive detection, PanSou/Nostr examples, Android Intent/DLNA/MediaSession, and WebView/CORS/cookie behavior.
