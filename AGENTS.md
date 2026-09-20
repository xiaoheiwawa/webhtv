# Repository Guidelines

## Project Structure & Module Organization

- Android Gradle project: `:app` (UI, playback, WebHome, local HTTP server, sync), `:catvod` (shared CatVod/CSP network layer), `:quickjs` (JS Spider runtime), `:chaquo` (Python Spider runtime).
- App Java lives in `app/src/main/java/com/fongmi/android/tv`, with flavor-specific sources under `app/src/mobile` and `app/src/leanback`.
- Shared CatVod code lives in `catvod/src/main/java/com/github/catvod`; JS helper libraries under `quickjs/src/main/assets/js/lib`.
- WebHome demo pages live in `demo/`; the full development reference is `docs/应用完整开发文档.md`.
- Dependencies are centralized in `gradle/libs.versions.toml`; local artifacts resolve from `third_party/maven` and `app/libs`.

## Build, Test, and Development Commands

Run Gradle through bash from the repo root (see `CLAUDE.md`):

```bash
bash gradlew :app:assembleMobileArm64_v8aRelease   # phone build; APK copied to Release/apk
bash gradlew :app:assembleLeanbackArm64_v8aRelease # TV build
bash gradlew :app:lint                            # lint all variants
bash gradlew test                                 # unit tests (no test tree exists yet)
```

Release signing comes from `local.properties` when present; otherwise builds fall back to debug signing.

## Coding Style & Naming Conventions

- Java: 4-space indentation, K&R braces, no trailing whitespace.
- Keep upstream FongMi/CatVod naming patterns, e.g. `Setting`/`Prefers` static accessors, `SpiderDebug`, `Utils` helpers.
- Gradle files use Groovy and the version catalog (`libs.versions.toml`); new dependencies must be pinned there, not inline.
- No formatter is configured; rely on `bash gradlew :app:lint` and match surrounding code.

## Testing Guidelines

- The repo currently has no `src/test` or `src/androidTest` trees. When adding tests, follow `CLAUDE.md` variant commands, e.g. `bash gradlew :app:testMobileArm64_v8aDebugUnitTest --tests 'com.fongmi.android.tv.ExampleTest'`.
- Instrumented tests run via `bash gradlew :app:connectedMobileArm64_v8aDebugAndroidTest`.
- Manually verify WebHome changes in the app (native bridge requires `window.fongmi`), not only in a desktop browser.

## Commit & Pull Request Guidelines

- Commit messages use conventional prefixes from the project history: `feat:`, `fix:`, `docs:`, `perf:`, `chore:`; summaries are short, imperative, and may be written in Chinese.
- Scope each commit to one logical change; keep WebHome/UI, server, and config-model changes separable.
- Pull requests should describe the change, link the relevant issue, and include screenshots or demo notes for UI and WebHome work.
- Do not commit generated outputs (`app/build`, `Release/apk`) or local signing properties.
