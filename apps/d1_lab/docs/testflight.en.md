# Start external testing with TestFlight

[日本語](testflight.md) · [Build instructions](building.en.md) · [Quick start](quickstart.en.md)

Use these steps to distribute D1 Lab to external iPhone and iPad testers. Submit the first build to TestFlight App Review, then enable an invitation link after approval. An App Store release is not required for TestFlight distribution.

## Register the app and build

1. Register a unique Bundle ID for D1 Lab in Apple Developer. Create an app in App Store Connect with iOS as its platform, D1 Lab as its name, and the same Bundle ID.
2. Prepare the runtime and Flutter dependencies using the [build instructions](building.en.md).
3. Open `apps/d1_lab/ios/Runner.xcworkspace` in Xcode. Set the distribution Team and registered Bundle Identifier under Runner → Signing & Capabilities. Keep signing information out of published source.
4. Create an Archive with a new build number. The example uses 18; use a number higher than any previously uploaded build for the same version.

   ```sh
   cd apps/d1_lab
   flutter build ipa --release --build-name 0.13.1 --build-number 18
   ```

5. Open the Archive in Xcode Organizer and run Validate App. After validation succeeds, use Distribute App → App Store Connect to upload it. Distribution can be restricted to TestFlight.
6. Wait for processing in App Store Connect and answer the encryption questions. Enter the description, test information and review notes below.

Use the Xcode and SDK versions required by Apple for uploads. From April 28, 2026, this requires Xcode 26 or later and the iOS 26 SDK or later. The app's minimum supported OS remains iOS 16. [Apple SDK requirements](https://developer.apple.com/news/upcoming-requirements/?id=02032026a)

To verify Archive creation without signing or uploading, add `--no-codesign` to the command. That Archive is not ready for distribution.

## Beta App Description

> D1 Lab lets you try Liquid AI's d1-3B and d1-omni-600M on iPhone and iPad. Evaluate text, photos and recordings with your own instructions and answer options, then inspect probabilities and processing time. Includes Japanese and English samples and saved custom tasks. Download models from Hugging Face inside the app; evaluation then runs locally with Metal. Downloaded models can be deleted. This is not an official Liquid AI app. Omni is experimental; evaluate answer quality for your own use case.

## What to Test

> Start with Choose a task → English → Review sentiment, then select d1-omni. Text evaluation only requires its approximately 407 MB model. Use Prepare model → Run decision, inspect the answer, probabilities and Total, then change the text and run again.
>
> • Model download, resume, deletion and redownload
> • Preparation and repeated-run speed, including the Total and Decision breakdown
> • Japanese/English switching, custom task names, categories and saving
> • Image samples with camera capture, photo selection and image resizing
> • Audio → Voice controls: record “Play music” or “Stop the music”, then try Japanese speech
> • Offline evaluation after download, and deletion of history, photos and recordings
>
> Photos and audio require approximately 263 MB of additional data for omni. The d1-3B model is approximately 1.67 GB, plus 583 MB for images. Download with sufficient free storage and a stable connection. Recordings are limited to 30 seconds and work with omni only. Include device model, iOS version, selected model and reproduction steps in bug reports. Do not attach personal inputs, photos or recordings.

## Review Notes

Copy the following into the TestFlight App Review notes. Turn off Sign-in required.

> D1 Lab is a local decision-model evaluation app. No account, purchase or subscription is required. The app does not require a separate inference service.
>
> Model weights are not bundled. Users explicitly download model data from the official LiquidAI repositories on Hugging Face. Downloads are checked against pinned sizes and SHA-256 hashes. The native inference runtime is bundled with the app; model downloads do not download executable app code. After download, evaluation works offline. User text, photos and recordings are processed on the device, not uploaded for inference.
>
> First test (smallest download):
> 1. Use the translation icon to select English.
> 2. Open Choose a task → English → Review sentiment.
> 3. Select d1-omni, then Download a model to start → Download files for this task. This text task downloads approximately 407 MB. Wait for completion on a stable connection with sufficient free storage.
> 4. Return to Try, tap Prepare model, then Run decision. Inspect the selected option, probabilities and processing time. Model answers are experimental and not guaranteed to match the sample's expected answer.
> 5. Change the review text and run again. The loaded model is reused.
>
> Image test: Choose a task → Images → Main photo color. Select omni, attach a photo with Choose photo or Take a photo, then download the required files. Omni images require an additional approximately 263 MB projector. Run decision. The photo's long-edge size can be changed in the photo card.
>
> Audio test: Choose a task → Audio → Voice controls. Omni is selected automatically. Download the required model/projector if needed, tap Record audio, say “Play music”, tap Stop and use, then Run decision. No transcript or additional context is required. Recordings stop after 30 seconds or when the app leaves the foreground. Camera and microphone permissions are requested only when those features are used. Audio was trained on English; Japanese accuracy is experimental.
>
> Models can be removed in Models → Delete model files. History and media can be removed in Models → Saved data. Custom tasks can be named, assigned a category and saved from the criteria editor. The interface supports English and Japanese. This is not an official Liquid AI app.

Enter the Feedback Email and review contact directly in App Store Connect. The Feedback Email is visible to testers. Keep contact details and signing certificates out of source control. [Test information fields](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)

## Privacy and encryption declarations

Use these implementation facts when answering the declarations:

- Text, photos, recordings, custom tasks and history are processed and stored on the device. They are not sent to a developer server.
- The app has no advertising, analytics or custom crash-upload service. TestFlight diagnostics and feedback use Apple's service.
- Model downloads connect over HTTPS to Hugging Face and its delivery hosts. Inputs and attachments are not sent, but the hosts receive connection information such as IP addresses. Hugging Face describes logging usage, device and connection information in its [privacy policy](https://huggingface.co/privacy).
- Downloads use Dart's `HttpClient`. Do not describe encryption as being provided exclusively by Apple's OS. SHA-256 verifies model integrity; the app has no custom encryption feature.

Answer App Privacy after checking the delivery hosts' data processing as well. Local inference alone does not establish a Data Not Collected declaration. Use the encryption questionnaire in App Store Connect to determine documentation requirements. Only set `ITSAppUsesNonExemptEncryption` to `false` after confirming exemption. [Apple encryption declarations](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)

Public privacy policy: [English](https://github.com/Corvelis/d1-lab/blob/codex/release-preparation/apps/d1_lab/docs/privacy.en.md) · [日本語](https://github.com/Corvelis/d1-lab/blob/codex/release-preparation/apps/d1_lab/docs/privacy.md)

## Enable external testing

1. Create an external testing group in TestFlight and add the uploaded build.
2. Check test information and review contact details, then submit to TestFlight App Review.
3. After approval, enable the group's public link. A small initial tester limit can help verify the rollout.
4. Testers install TestFlight on iPhone or iPad, then use the invitation link to install D1 Lab. They can begin with the [quick start](quickstart.en.md).

Builds can be tested for up to 90 days. Prepare a new build before expiry. [Inviting external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)

## Before submission

- [ ] Complete download, preparation and evaluation from a fresh installation on a physical device
- [ ] Test text and images with both models and microphone recording with omni on a physical device
- [ ] Confirm the app remains usable when camera, photo or microphone access is denied
- [ ] Check saved tasks/history after restart and deletion of models and saved data
- [ ] Check layout and rotation on iPhone and iPad
- [ ] Check the Release Archive's privacy manifests and signing, and pass Validate App
- [ ] Enter bilingual test information, public privacy policy, Feedback Email and review contact
- [ ] Complete encryption declarations and obtain document approval if required
