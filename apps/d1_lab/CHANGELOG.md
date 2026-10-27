# Changelog

## 0.14.0

- Add LFM3 d1-2B (Q4_K_M) and d1-Omni-2B (Q8_0), with verified in-app model/projector download, import and deletion.
- Run the new models locally with Metal using DecisionRuntime 0.3.0. Keep existing d1-3B and d1-omni-600M downloads and saved tasks usable.
- Choose two models for comparison; compare both Omni models with the same recording.
- Display LFM3 score medians and input throughput, alongside Total, Decision and media timing.
- Add Japanese and English everyday-sound samples and update bilingual guides.
- GGUF support covers Choice, Noul and Score. Other LFM3 output types and video are not included.

## 0.13.2

- Reduce 3B Metal output projection to the answer candidates.
- Use DecisionRuntime 0.2.1. Omni and CPU inference settings are unchanged.

## 0.13.1

- Use D1 Lab branding and the app background color on the iOS launch screen.
- Explain TestFlight diagnostics and feedback in the Japanese and English privacy policies.
- Add bilingual external-testing instructions, beta descriptions and review notes.

## 0.13.0

- Manage photo and recording storage from Models → Saved data.
- Remove unused media while retaining files used by history or the current input.
- Delete all history and imported media with confirmation. Models and saved tasks are kept.
- Remove unused media when deleting individual history entries.
- Read the privacy policy in Japanese or English without a network connection.
- Keep models ready for repeated decisions and show Total, Decision and input processing speed.
- Create named tasks under Text, Images or Audio, or use Automatic.

Requires iOS 16 or later, or macOS 14 or later on Apple Silicon. Models download separately from Hugging Face. Android inference is not included.
