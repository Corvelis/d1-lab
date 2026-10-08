# ビルドと起動

[アプリの使い方](../README.md) · [English](building.en.md) · [リリースの作成](distributing.md)

アプリをビルドしてiPhoneやMacで起動する手順です。ソースを取得・展開し、`apps` と `native` があるフォルダー（リポジトリのルート）をターミナルで開いてください。

## 必要なもの

- Apple Silicon Mac
- Flutter 3.32.8以降（Dart 3.8.1以降）
- XcodeとiOS SDK、CocoaPods
- Python 3.10以降
- ソースからランタイムを作る場合はCMake 3.22以降

iPhoneはiOS 16以上、Macで試す場合はmacOS 14以上が必要です。iOSシミュレータはarm64に対応します。

## 1. 推論ランタイムを準備する

リポジトリのルートから、次のどちらかを実行します。

### ビルド済み版を使う（推奨）

リリースに添付された `DecisionRuntime-0.2.0-apple-arm64.zip` と `SHA256SUMS` をリポジトリのルートへダウンロードします。その後、次を実行します。

```sh
runtime_sha=$(awk '$2 == "DecisionRuntime-0.2.0-apple-arm64.zip" {print $1}' SHA256SUMS)
python3 native/decision_bridge/scripts/prepare_runtime.py \
  --archive DecisionRuntime-0.2.0-apple-arm64.zip --sha256 "$runtime_sha"
```

アーカイブのチェックサム、ソースとの対応、ライブラリとライセンスの内容を確認して配置します。検証に失敗した場合は既存のランタイムを置き換えません。ソースの版と一致するリリースを使用してください。

### ソースから作る

```sh
python3 native/decision_bridge/scripts/prepare_runtime.py --source
```

固定版のllama.cppを取得して検証し、d1用のパッチを適用してビルドします。初回は数分かかります。ビルド済み版を使う場合、この手順とCMakeは不要です。

## 2. アプリを起動する

```sh
cd apps/d1_lab
flutter pub get
flutter devices
```

**iPhone:** USBで接続し、端末を信頼します。端末の設定でDeveloper Modeを有効にします。`ios/Runner.xcworkspace` をXcodeで開き、Runnerの「Signing & Capabilities」で自分のTeamと固有のBundle Identifierを設定します。

```sh
flutter run --release -d <device-id>
```

`<device-id>` は `flutter devices` に表示された値に置き換えてください。

**Mac:**

```sh
flutter run --release -d macos
```

**iOSシミュレータ:**

```sh
flutter run -d <simulator-id>
```

シミュレータには実カメラがありません。写真は写真ピッカーまたはファイル取り込みで試してください。速度の比較には実機のreleaseビルドを使ってください。

## 3. モデルを取得する

起動後、タスクとモデルを選び、「モデルを取得して始める」から取得します。画像・音声タスクでは必要な追加データも取得します。モデルはアプリのビルドに含める必要がありません。

## よくある問題

| 状況 | 対処 |
| --- | --- |
| XCFrameworkが見つからない | 手順1を実行してから、再度ビルドする |
| CocoaPodsの依存関係が解決しない | `flutter pub get` の後、`ios` または `macos` ディレクトリで `pod install` を実行する |
| iPhoneの署名エラー | XcodeでTeam、Bundle Identifier、接続した端末を確認する |
| モデル取得が途中で止まる | 通信と空き容量を確認し、モデル画面で「取得・再開」を押す |
| 写真・録音の判定を開始できない | 添付と追加データの取得状態を確認する |
| 入力が上限を超える | 入力を短くするか、実行設定の入力上限を増やす |

## 開発時の確認

```sh
cd apps/d1_lab
flutter analyze
flutter test
```

推論ライブラリの配布用ZIPは、ランタイムをビルドした後に作れます。

```sh
python3 native/decision_bridge/scripts/package_runtime.py --output dist/runtime
```

このコマンドはリポジトリのルートから実行してください。ソースが変更されている場合は、先にランタイムを作り直します。
