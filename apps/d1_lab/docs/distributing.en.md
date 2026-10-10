# Creating a release

[日本語](distributing.md) · [Build instructions](building.en.md)

## Source and runtime

Publish source under Apache-2.0. Keep models separate; the app downloads them from official Hugging Face repositories. Retain dependency copyright and license notices. Models have separate LFM Open License conditions.

Prepare the runtime in a fresh source checkout and run:

```sh
cd apps/d1_lab
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build macos --release
flutter build ios --release --no-codesign
```

Attach the runtime ZIP and SHA256SUMS to GitHub Release using the names in the build guide. App version 0.13.1 uses runtime 0.2.0. Use CHANGELOG.md for release notes. Prepare the Release as a draft before publication.

Release files can include source, the runtime ZIP, checksums and the bilingual guides. Do not attach model GGUF files, signing certificates, credentials or personal run history.

## Mac app

The app supports Apple Silicon running macOS 14 or later. Sign a copy of the built app with a Developer ID Application certificate. Run this from the repository root with a new output directory:

```sh
python3 native/decision_bridge/scripts/package_macos.py \
  --app "apps/d1_lab/build/macos/Build/Products/Release/D1 Lab.app" \
  --identity "Developer ID Application" \
  --output dist/macos --notary-profile d1-lab-notary
```

Replace d1-lab-notary with an existing notarytool profile stored in your Mac's Keychain. Do not place credentials in source or scripts. With multiple certificates, pass the identity's SHA-1 from `security find-identity -v -p codesigning` instead.

When Apple's status is Accepted, run:

```sh
python3 native/decision_bridge/scripts/finish_macos.py \
  --directory dist/macos --notary-profile d1-lab-notary
```

The script requires Accepted, staples and validates the ticket, verifies signatures and checks Gatekeeper before updating the ZIP and checksums. Verify downloading, extracting and launching on another Mac before attaching the ZIP and SHA256SUMS to Release. Notarization does not validate model accuracy.

[Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## iPhone app

Follow the [bilingual TestFlight guide](testflight.en.md) for external testing, including app registration, Archive creation, beta descriptions, review notes and invitation links.

Set a unique Bundle Identifier and distribution Team in Xcode, then create an Archive. Validate it in Organizer and upload it to App Store Connect. The first external TestFlight build requires review. A development IPA restricted to registered devices is not a general distribution package.

Provide TestFlight test information and review contact details. For a later App Store release, also provide Japanese and English store descriptions, screenshots, a support URL and a published privacy-policy URL. Complete privacy disclosures after checking model delivery services and dependency SDK data handling as well as the implementation that keeps decision inputs on-device.

Review notes should explain downloading models in the app and running text, image and audio samples. Decisions run on-device; model files are downloaded as additional data.

[TestFlight](https://developer.apple.com/testflight/)
