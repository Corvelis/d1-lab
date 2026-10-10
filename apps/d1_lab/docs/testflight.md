# TestFlightで外部テストを始める

[English](testflight.en.md) · [ビルド手順](building.md) · [使い方](quickstart.md)

D1 LabをiPhone・iPadの外部テスターへ配布するための手順です。最初のビルドをTestFlight App Reviewへ提出し、承認後に招待リンクを有効にします。TestFlightでの配布に、App Storeでの一般公開は必要ありません。

## アプリ登録とビルド

1. Apple DeveloperでD1 Lab用の固有のBundle IDを登録します。App Store Connectで新規アプリを作成し、プラットフォームはiOS、名前はD1 Lab、同じBundle IDを指定します。
2. [ビルド手順](building.md)でランタイムとFlutterの依存関係を準備します。
3. Xcodeで`apps/d1_lab/ios/Runner.xcworkspace`を開き、RunnerのSigning & Capabilitiesで配布用Teamと登録したBundle Identifierを設定します。公開するソースには署名情報を保存しないでください。
4. 新しいビルド番号を指定してArchiveを作成します。以下の18は例です。同じバージョンでアップロード済みの番号より大きくします。

   ```sh
   cd apps/d1_lab
   flutter build ipa --release --build-name 0.13.1 --build-number 18
   ```

5. Xcode OrganizerでArchiveを開き、Validate Appを実行します。成功したらDistribute App → App Store Connectでアップロードします。配布先はTestFlightのみに設定できます。
6. App Store Connectで処理完了を待ち、暗号化の質問に回答します。TestFlightのテスト情報に、下記の紹介文・テスト内容・審査メモを入力します。

アップロードにはAppleが要求するXcodeとSDKの版を使います。2026年4月28日以降はXcode 26以上とiOS 26 SDK以上が必要です。最低対応OSはiOS 16のままです。[AppleのSDK要件](https://developer.apple.com/news/upcoming-requirements/?id=02032026a)

署名・アップロードを行わずArchiveまで確認する場合は、同じコマンドに`--no-codesign`を付けます。このArchiveをそのまま配布することはできません。

## テスト用の紹介文

App Store Connectの日本語の「ベータ版Appの説明」へ使えます。

> D1 Labは、Liquid AIのd1-3Bとd1-omni-600MをiPhone・iPadで試すアプリです。文章・写真・録音について、自然言語の指示と候補を指定して判定し、答えの確率と処理時間を確認できます。日本語・英語のサンプルと、自分のタスクの保存に対応しています。モデルはアプリ内でHugging Faceから取得し、取得後の判定は端末内のMetalで行います。モデルファイルは削除できます。Liquid AIの公式アプリではありません。omniは実験用モデルで、答えの正しさは用途ごとに確認してください。

## テストしてほしいこと

ビルドの日本語の「テスト内容」へ使えます。

> 最初は「タスクを選ぶ」→「日本語」→「口コミの印象」を選び、モデルをd1-omniに変更してください。文章だけなら約407 MBの取得で試せます。「モデルを準備」→「判定を実行する」で、答え・確率・Totalを確認し、文章を変更して再実行してください。
>
> ・モデルの取得、途中からの再開、削除と再取得
> ・事前準備後と繰り返し実行時の速度、TotalとDecisionの内訳
> ・日本語と英語の切り替え、自分のタスクの名前・登録先・保存
> ・「画像」のサンプルで、カメラ撮影・写真選択・画像サイズ変更
> ・「音声」→「声で操作を選ぶ」で録音。「Play music」「Stop the music」などの英語から始め、日本語も試してください
> ・モデル取得後のオフライン判定、履歴・写真・録音の削除
>
> 写真・音声では約263 MBの追加データが必要です。d1-3Bは本体が約1.67 GB、画像用の追加データが約583 MBです。十分な空き容量と安定した通信環境で取得してください。音声は最大30秒でomniのみ対応します。不具合の報告には、機種・iOSの版・モデル・再現手順を添えてください。個人情報を含む入力や写真・録音は添付しないでください。

## 審査用メモ

Appleの審査担当者向けには、[英語の審査メモ](testflight.en.md#review-notes)を使えます。サインイン必須はオフです。アプリの利用にアカウントや購入は不要です。

フィードバック用メールと審査連絡先はApp Store Connectへ直接入力します。フィードバック用メールはテスターに表示されます。連絡先や署名証明書をソースへ入れないでください。[テスト情報の項目](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)

## プライバシーと暗号化の申告

申告には次の実装上の事実を使います。

- 文章・写真・録音・自分のタスク・履歴は端末内で処理・保存します。開発者のサーバーへ送信しません。
- アプリに広告、アクセス解析、独自のクラッシュ送信はありません。TestFlightの診断とフィードバックはAppleの仕組みです。
- モデル取得時はHugging Faceと配信先へHTTPS接続します。入力や添付ファイルは送りませんが、接続先にはIPアドレスなどの通信情報が渡ります。Hugging Faceは利用・端末・接続情報の記録について[プライバシーポリシー](https://huggingface.co/privacy)で説明しています。
- ダウンロードはDartの`HttpClient`を使います。AppleのOSだけが暗号処理を提供する構成とは申告しないでください。SHA-256はモデルファイルの整合性検証に使い、独自の暗号化機能はありません。

App Privacyは配信先のデータ処理も確認して回答します。「データを収集しない」をローカル推論だけから自動で選ばないでください。暗号化についてはApp Store Connectの質問で必要書類を確認し、免除が確認できた場合だけ`ITSAppUsesNonExemptEncryption`を`false`へ設定します。[Appleの暗号化申告](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)

公開プライバシーポリシー: [日本語](https://github.com/Corvelis/d1-lab/blob/codex/release-preparation/apps/d1_lab/docs/privacy.md) · [English](https://github.com/Corvelis/d1-lab/blob/codex/release-preparation/apps/d1_lab/docs/privacy.en.md)

## 外部テストを有効にする

1. TestFlightで外部テスターのグループを作り、アップロードしたビルドを追加します。
2. テスト内容と審査連絡先を確認して、TestFlight App Reviewへ提出します。
3. 承認後、グループの公開リンクを有効にします。最初は人数の上限を小さく設定して動作を確認できます。
4. テスターはiPhone・iPadにTestFlightをインストールし、招待リンクからD1 Labをインストールします。[最初の判定](quickstart.md)から試せます。

ビルドのテスト期間は最大90日です。期限前に新しいビルドを用意します。[外部テスターの招待](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)

## 提出前の確認

- [ ] モデル未取得の状態から、ダウンロード・準備・判定まで実機で完了する
- [ ] d1-3Bとomniの文章・画像、omniのマイク録音を実機で確認する
- [ ] カメラ・写真・マイクの許可を拒否しても、アプリが使い続けられる
- [ ] 再起動後の保存タスク・履歴、モデルと保存データの削除を確認する
- [ ] iPhoneとiPadで画面の表示と回転を確認する
- [ ] Release Archiveのプライバシーマニフェストと署名を確認し、Validate Appに成功する
- [ ] 日英のテスト情報、公開プライバシーポリシー、フィードバック用メール、審査連絡先が入力済み
- [ ] 暗号化の申告を完了し、必要な場合は書類の承認を受ける
