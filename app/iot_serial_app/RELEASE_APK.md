# 如何生成 Android Release APK

本文说明在 **`iot_serial_app` 项目根目录** 下如何打出可安装的 release APK。

## 前置条件

- 已安装 **Flutter SDK**，且 `flutter doctor` 无阻塞项（至少 Android toolchain 可用）。
- 已安装 **Android SDK**（通过 Android Studio 或 `cmdline-tools`），并配置好 `ANDROID_HOME` / `ANDROID_SDK_ROOT`。
- 在项目根目录执行过依赖拉取：

```bash
cd /path/to/iot_serial_app
flutter pub get
```

## 一键生成 Release APK

在项目根目录执行：

```bash
flutter build apk --release
```

### 产物位置

- **默认单包（含所有 ABI，体积较大）**  
  `build/app/outputs/flutter-apk/app-release.apk`

- **按 CPU 架构分包（减小单个 APK 体积，上架或分发时常用）**  

```bash
flutter build apk --release --split-per-abi
```

  生成例如：

  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-x86_64-release.apk`（模拟器/少数设备）

安装到手机时，选与设备架构匹配的包即可（多数手机为 **arm64-v8a**）。

## 版本号

- 在根目录 **`pubspec.yaml`** 的 `version` 字段控制 Android 的 **versionName** 与 **versionCode**，例如：

  `version: 1.0.0+1` → `1.0.0` 为对外版本名，`+1` 为内部递增的 versionCode。

- 也可在构建时临时覆盖（不修改 `pubspec.yaml`）：

```bash
flutter build apk --release --build-name=1.0.1 --build-number=2
```

## 当前工程里的签名说明（重要）

`android/app/build.gradle.kts` 里 **release** 目前使用的是 **debug 签名**（便于本地直接 `flutter run --release`）。这样生成的 APK **可以安装、自测**，但 **不适合** 作为正式上架或对外发布的唯一签名方案。

若需要 **正式发布签名**：

1. 用 `keytool` 生成 keystore（或使用 Play App Signing 由 Google 托管）。
2. 在 `android` 下配置 `key.properties`（不要提交到 Git），并在 `build.gradle.kts` 中为 `release` 配置 `signingConfigs`。
3. 具体步骤见官方文档：[Sign the app](https://docs.flutter.dev/deployment/android#signing-the-app)。

## 可选：Google Play 上架用 AAB

若上架 Google Play，通常提交 **App Bundle** 而非 APK：

```bash
flutter build appbundle --release
```

产物：`build/app/outputs/bundle/release/app-release.aab`

## 常用命令小结

| 目的           | 命令 |
|----------------|------|
| 单文件 release APK | `flutter build apk --release` |
| 分架构 APK     | `flutter build apk --release --split-per-abi` |
| Play 上架 AAB  | `flutter build appbundle --release` |
| 清理后重编     | `flutter clean && flutter pub get && flutter build apk --release` |

安装到已连接设备（调试用）：

```bash
flutter install --release
```

（需先 `flutter devices` 能看到设备，且设备允许 USB 安装。）
