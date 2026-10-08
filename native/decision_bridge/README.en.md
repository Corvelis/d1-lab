# decision_bridge

[日本語](README.md)

The Flutter inference plugin for D1 Lab. It runs d1-3B / d1-omni-600M with CPU or Metal on iOS 16+ and macOS 14+ on Apple Silicon.

See the [D1 Lab guide](../../apps/d1_lab/docs/README.en.md) to try the app, or the [build instructions](../../apps/d1_lab/docs/building.en.md) to prepare it.

## Prepare the runtime

Run this command from the repository root:

```sh
python3 native/decision_bridge/scripts/prepare_runtime.py --source
```

The script verifies the pinned llama.cpp source with SHA-256, applies the d1 patches and builds an XCFramework for iOS devices, the arm64 iOS simulator and macOS. Metal kernel source is embedded in the framework.

The same setup script can verify and install a prebuilt runtime. See the [build instructions](../../apps/d1_lab/docs/building.en.md) for that method. Use a runtime matching this package: general llama.cpp binaries do not include this package's d1 patches.

## Source and licenses

The upstream revision and archive SHA-256 are pinned in `runtime.lock.json`. `patch_runtime.py` and `patch_media.py` add the d1 decision head and media processing. The C API is in `include/decision.h`.

This package's source is [Apache-2.0](LICENSE). Dependency licenses are listed in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md) and included in `licenses/`. Model licenses are separate.
