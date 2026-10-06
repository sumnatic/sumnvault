# Release Builds

The release script is `tool/build_release.ps1`.

## Windows

```powershell
.\tool\build_release.ps1 -Target windows
```

It runs analysis and tests, builds the release bundle, creates `dist/sumnvault-windows-x64.zip`, and writes `SHA256SUMS.txt`.

## Android

```powershell
.\tool\build_release.ps1 -Target android
```

To generate only the installable APK when the local Gradle/NDK setup cannot strip native symbols for an App Bundle:

```powershell
.\tool\build_release.ps1 -Target android -SkipAndroidBundle
```

Before running it, install Android SDK Command-line Tools, accept SDK licenses with `flutter doctor --android-licenses`, and ensure `flutter doctor` reports a healthy Android toolchain. The script produces a release APK and an Android App Bundle in `dist/` only when both builds succeed.

The current Gradle template uses the debug signing key so local release builds can run. Configure a private release keystore and signing properties before publishing; never distribute the debug-signed artifacts. If Gradle cannot strip native symbols, repair the Android NDK/cmdline-tools installation before accepting the AAB; the release script intentionally stops instead of copying a partial bundle.

## Linux and macOS

These builds must run on native hosts because Flutter does not reliably cross-compile desktop targets:

```bash
pwsh tool/build_release.ps1 -Target linux
pwsh tool/build_release.ps1 -Target macos
```

Linux creates an x64 zip bundle. macOS creates an `.app` zip. `-Target all` runs every target sequentially and is intended for CI with native runners; it fails explicitly when a desktop target is unavailable on the current host.

Every target runs `flutter pub get`, `flutter analyze`, and `flutter test` before building. Artifacts are placed under `dist/` and should receive platform signing/notarization as part of the distribution pipeline.
