# Third-party notices

The DecisionRuntime binary includes the following software. The license texts are included in `native/decision_bridge/licenses/` and in every runtime archive.

| Software | License file |
| --- | --- |
| llama.cpp / ggml | `native/decision_bridge/licenses/llama.cpp-MIT.txt` |
| nlohmann/json | `native/decision_bridge/licenses/json-MIT.txt` |
| stb_image | `native/decision_bridge/licenses/stb_image.txt` |
| miniaudio and bundled audio decoders | `native/decision_bridge/licenses/miniaudio.txt` |

The llama.cpp revision is recorded in `native/decision_bridge/runtime.lock.json`. The d1 changes are provided in `native/decision_bridge/scripts/patch_runtime.py` and `native/decision_bridge/scripts/patch_media.py`.

Flutter package dependencies retain their own licenses. The app exposes their notices through its license screen. Liquid AI model files are downloaded separately and are governed by the LFM Open License included in the app.

## App dependencies

The iOS app uses the following libraries for photo and file selection. Their original license texts are bundled with the app and shown in its license screen.

| Software | License | Original license text |
| --- | --- | --- |
| SDWebImage | MIT | [License](apps/d1_lab/assets/licenses/SDWebImage-MIT.txt) |
| SwiftyGif | MIT | [License](apps/d1_lab/assets/licenses/SwiftyGif-MIT.txt) |
| DKImagePickerController | MIT | [License](apps/d1_lab/assets/licenses/DKImagePickerController-MIT.txt) |
| DKPhotoGallery | MIT | [License](apps/d1_lab/assets/licenses/DKPhotoGallery-MIT.txt) |

Flutter and Dart package notices are included in the app’s license screen. See the [DecisionRuntime notices](native/decision_bridge/THIRD_PARTY_NOTICES.md) for the native inference libraries.
