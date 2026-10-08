# リリースの作成

[English](distributing.en.md) · [ビルド手順](building.md)

## ソースとランタイム

ソースはApache-2.0で公開します。モデルは含めず、アプリからHugging Faceの公式配布元へ接続して取得します。依存ライブラリのライセンス・著作権表示を残してください。モデルには別途LFM Open Licenseが適用されます。

新しく取得したソースでランタイムを準備し、次を確認します。

```sh
cd apps/d1_lab
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build macos --release
flutter build ios --release --no-codesign
```

ランタイムのZIPとSHA256SUMSは、ビルド手順に記載した名前でGitHub Releaseに添付します。アプリの版は0.13.0、対応ランタイムは0.2.0です。CHANGELOG.mdをリリースノートに使えます。公開前はReleaseを下書きとして作成してください。

公開するファイルの候補は、ソース、ランタイムZIP、チェックサム、日英の説明書です。モデルのGGUF、署名証明書、認証情報、個人の実行履歴を添付しないでください。

## Macアプリ

Apple SiliconのmacOS 14以上が対象です。Developer ID Application証明書を使い、ビルドしたアプリのコピーへ署名します。以下はリポジトリのルートで実行します。出力先は新しいフォルダーを指定してください。

```sh
python3 native/decision_bridge/scripts/package_macos.py \
  --app "apps/d1_lab/build/macos/Build/Products/Release/D1 Lab.app" \
  --identity "Developer ID Application" \
  --output dist/macos --notary-profile d1-lab-notary
```

`d1-lab-notary`は、事前に自分のMacのKeychainへ保存したnotarytoolプロファイル名に置き換えます。認証情報はソースやスクリプトへ書き込まないでください。証明書が複数ある場合は、`security find-identity -v -p codesigning`で確認した署名用SHA-1を`--identity`に指定できます。

公証の結果がAcceptedになったら、次を実行します。Accepted以外の状態では配布可能として扱いません。

```sh
python3 native/decision_bridge/scripts/finish_macos.py \
  --directory dist/macos --notary-profile d1-lab-notary
```

チケットの添付、署名、Gatekeeper検証に成功すると、ZIPとチェックサムを更新します。別のMacでもダウンロード・展開・起動を確認してから、ZIPとSHA256SUMSをReleaseへ添付します。公証済みであることは、モデルの判断精度を保証するものではありません。

[Appleの公証手順](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## iPhoneアプリ

Xcodeで固有のBundle Identifierと配布用Teamを設定し、Archiveを作成します。OrganizerのValidate Appに成功した後、App Store Connectへアップロードします。TestFlightの外部テストには初回ビルドの審査が必要です。開発用の端末登録を前提にしたIPAを一般配布用として案内しないでください。

App Store Connectには、日英の説明、スクリーンショット、サポートURL、公開済みプライバシーポリシーURLを設定します。プライバシー申告は入力を外部へ送信しない実装に加え、モデル配信先と依存SDKのデータ処理を確認したうえで回答してください。

審査用メモには、モデルをアプリ内で取得する手順と、文章・画像・音声のサンプル操作を記載します。判定は端末内で行い、モデルファイルは追加データとして取得する構成です。

[TestFlight](https://developer.apple.com/testflight/)
