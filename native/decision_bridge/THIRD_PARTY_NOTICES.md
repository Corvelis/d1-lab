# Third-party notices

The DecisionRuntime binary includes the following software. The license texts are included in `licenses/` and in every runtime archive.

| Software | License file |
| --- | --- |
| llama.cpp / ggml | `licenses/llama.cpp-MIT.txt` |
| nlohmann/json | `licenses/json-MIT.txt` |
| stb_image | `licenses/stb_image.txt` |
| miniaudio and bundled audio decoders | `licenses/miniaudio.txt` |

The llama.cpp revision is recorded in `runtime.lock.json`. The d1 changes are provided in `scripts/patch_runtime.py` and `scripts/patch_media.py`.

Flutter package dependencies retain their own licenses. The app exposes their notices through its license screen. Liquid AI model files are downloaded separately and are governed by the LFM Open License included in the app.
