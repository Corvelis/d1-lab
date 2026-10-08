# Build and run

[App guide](README.en.md) · [日本語](building.md) · [Creating a release](distributing.en.md)

This guide builds and runs the app on an iPhone or Mac. Obtain and extract the source, then open a terminal in the folder containing `apps` and `native` (the repository root).

## Requirements

- Apple Silicon Mac
- Flutter 3.32.8 or later, with Dart 3.8.1 or later
- Xcode with the iOS SDK, and CocoaPods
- Python 3.10 or later
- CMake 3.22 or later when building the runtime from source

Targets: iOS 16+, macOS 14+, and the arm64 iOS simulator.

## 1. Prepare the inference runtime

From the repository root, choose either method.

### Use a prebuilt release (recommended)

Download the release's `DecisionRuntime-0.2.0-apple-arm64.zip` and `SHA256SUMS` into the repository root, then run:

```sh
runtime_sha=$(awk '$2 == "DecisionRuntime-0.2.0-apple-arm64.zip" {print $1}' SHA256SUMS)
python3 native/decision_bridge/scripts/prepare_runtime.py \
  --archive DecisionRuntime-0.2.0-apple-arm64.zip --sha256 "$runtime_sha"
```

The script verifies the archive checksum, matching source version, libraries and licenses before installing. Failed verification leaves the existing runtime unchanged. Use the release corresponding to your source checkout.

### Build from source

```sh
python3 native/decision_bridge/scripts/prepare_runtime.py --source
```

The script verifies the pinned llama.cpp archive, applies the d1 patches and builds the XCFramework. The first build takes a few minutes. Skip this step and CMake when using a prebuilt release.

## 2. Run the app

```sh
cd apps/d1_lab
flutter pub get
flutter devices
```

**iPhone:** Connect by USB, trust the Mac and enable Developer Mode on your phone. Open `ios/Runner.xcworkspace` in Xcode. In Runner's Signing & Capabilities, select your own Team and a unique Bundle Identifier.

```sh
flutter run --release -d <device-id>
```

Replace `<device-id>` with the value shown by `flutter devices`.

**Mac:**

```sh
flutter run --release -d macos
```

**iOS simulator:**

```sh
flutter run -d <simulator-id>
```

The simulator has no physical camera. Use the photo picker or file import instead. Measure speed with a release build on a real device.

## 3. Download a model

Select a task and model, then follow the app's download prompt. Image and audio tasks also download the required projector. Models do not need to be included in your build.

## Troubleshooting

| Problem | Try this |
| --- | --- |
| Missing XCFramework | Complete step 1 before building |
| CocoaPods dependencies fail | Run `flutter pub get`, then `pod install` inside `ios` or `macos` |
| iPhone signing error | Check your Team, Bundle Identifier and connected device in Xcode |
| Interrupted model download | Check connectivity and free storage, then resume in Models |
| Photo or recording cannot run | Check the attachment and required projector download |
| Input exceeds the limit | Shorten the input or increase the input limit in run settings |

## Development checks

```sh
cd apps/d1_lab
flutter analyze
flutter test
```

After building the runtime, create its release archive from the repository root:

```sh
python3 native/decision_bridge/scripts/package_runtime.py --output dist/runtime
```

Rebuild the runtime before packaging if its source has changed.
