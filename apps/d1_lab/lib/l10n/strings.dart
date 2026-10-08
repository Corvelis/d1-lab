import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

String resolveLanguage(String preference, List<Locale> deviceLocales) {
  if (preference == 'ja' || preference == 'en') return preference;
  for (final locale in deviceLocales) {
    if (locale.languageCode == 'ja' || locale.languageCode == 'en') {
      return locale.languageCode;
    }
  }
  return 'en';
}

/// UI messages only. Drafts, saved tasks and model answers are never translated.
/// Placeholders preserve inserted values instead of rewriting user content.
class AppStrings {
  const AppStrings(this.languageCode);
  final String languageCode;
  static const supportedLocales = [Locale('ja'), Locale('en')];
  static const delegate = _StringsDelegate();
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings('ja');

  String text(String source, [Map<String, Object?> values = const {}]) {
    var result = languageCode == 'en'
        ? englishMessages[source] ?? source
        : source;
    // A single replacement pass leaves braces inside inserted user text intact.
    return result.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) =>
          values.containsKey(match[1]) ? '${values[match[1]]}' : match[0]!,
    );
  }

  String progress(String source) => status(
    source
        .replaceFirst(RegExp(r'^.*?\.gguf · '), '')
        .replaceAll('SHA-256を確認中', 'モデルを確認中')
        .replaceAll('SHA-256を検証中', 'ファイルを確認中'),
  );

  /// Localize runtime/download diagnostics at presentation time. Keeping their
  /// source messages in the controller lets an active error change language too.
  String status(String source) {
    final message = source.replaceFirst(
      RegExp(r'^(FormatException|Bad state|HttpException): '),
      '',
    );
    if (languageCode != 'en') return message;
    if (englishMessages.containsKey(message)) return text(message);
    final asset = RegExp(
      r'^(.+\.gguf) · (.+)$',
      dotAll: true,
    ).firstMatch(message);
    if (asset != null) return '${asset[1]} · ${status(asset[2]!)}';
    for (final (template, expression, names) in _statusTemplates) {
      final match = expression.firstMatch(message);
      if (match != null) {
        return text(template, {
          for (var i = 0; i < names.length; i++)
            names[i]: status(match[i + 1]!),
        });
      }
    }
    // PlatformException wrappers may contain a known native error plus details.
    var result = message;
    for (final entry in _staticMessages) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  static final _staticMessages =
      englishMessages.entries
          .where((e) => !e.key.contains('{') && e.key.length > 3)
          .toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
  static final _statusTemplates = _buildTemplates();
  static List<(String, RegExp, List<String>)> _buildTemplates() {
    final templates =
        englishMessages.keys.where((s) => s.contains('{')).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (final source in templates)
        (
          source,
          RegExp(
            '^${RegExp.escape(source).replaceAllMapped(RegExp(r'\\\{(\w+)\\\}'), (_) => '(.*?)')}\$',
            dotAll: true,
          ),
          [
            for (final match in RegExp(r'\{(\w+)\}').allMatches(source))
              match[1]!,
          ],
        ),
    ];
  }
}

extension StringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}

class _StringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => ['ja', 'en'].contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale.languageCode));
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

const englishMessages = <String, String>{
  '保存データ': 'Saved data',
  '写真・録音': 'Photos and recordings',
  '{p0}ファイル': '{p0} files',
  '使っていない素材を削除': 'Remove unused media',
  '履歴と写真・録音をすべて削除': 'Delete all history and media',
  '履歴と写真・録音を削除しますか？': 'Delete history and media?',
  '使っていない素材を削除しますか？': 'Remove unused media?',
  'すべての履歴と、取り込んだ写真・録音を削除します。現在の添付も外れます。モデルと自分のタスクは残ります。元の写真や取り込む前のファイルは変更しません。この操作は取り消せません。':
      'Delete all history and imported photos and recordings, including the current attachment. Models and saved tasks are kept. Your original photos and files are unchanged. This cannot be undone.',
  '履歴と現在の入力が使っている素材は残します。アプリに保存した、使っていない写真・録音だけを削除します。この操作は取り消せません。':
      'Keep media used by history or the current input. Only unused photos and recordings stored in the app are deleted. This cannot be undone.',
  'モデルはモデル画面、自分のタスクはタスク一覧から削除できます。':
      'Delete models from Models and saved tasks from the task list.',
  '使用容量を確認できませんでした': 'Could not check storage usage',
  '保存データを削除中': 'Deleting saved data',
  '保存データを削除しました': 'Saved data deleted',
  'プライバシーポリシー': 'Privacy policy',
  '説明を読み込めませんでした': 'Could not load this information',
  '履歴を削除しますか？': 'Delete this history entry?',
  'この履歴と、ほかの履歴や現在の入力が使っていない素材を削除します。この操作は取り消せません。':
      'Delete this history entry and media unused by other history or the current input. This cannot be undone.',
  'ファイルを取り込む': 'Import a file',
  '{p0}：モデルを確認中': '{p0}: Checking the model',
  "編集したタスク": "Edited task",
  "待機を終了します。モデルファイルは残ります。":
      "Stop keeping the model ready. Downloaded files are kept.",
  "モデル画面でダウンロードできます。": "Download the model from Models.",
  "先に読み込んで、すぐ判定できる状態にします。": "Load the model now so it is ready to run.",
  "写真・音声を追加": "Add a photo or audio",
  "入力と判定条件を保存します。写真・音声は次回選び直してください。":
      "Save the input and criteria. Add photos or audio again next time.",
  "同じ入力で、答えと速度を見比べます。": "Compare answers and speed using the same input.",
  "{p0}件の質問 · {p1}": "{p0} questions · {p1}",
  "これまでの答えと速度を確認できます。": "Review past answers and speed.",
  "ダウンロード後はオフラインで使えます。": "Works offline after downloading.",
  "Hugging Faceの公式配布元から取得します。":
      "Download from the official Hugging Face repositories.",
  "モデルを読み込んだまま待機": "Keep the model ready",
  "繰り返しの判定が速くなります。アプリを離れると待機を終了します。":
      "Speeds up repeat runs. The model is released when you leave the app.",
  "モデルの推奨設定を使います。": "Use the recommended model settings.",
  "詳細設定": "Advanced settings",
  "モデル関連のファイル（{p0} MB）を削除します。タスクと履歴は残ります。":
      "Delete model files ({p0} MB). Tasks and history are kept.",
  "✓ 取得済み": "✓ Downloaded",
  "小さくすると処理が軽くなります。": "Smaller images take less processing.",
  "録音は最大30秒 · omniで判定": "Up to 30 seconds · Runs with omni",
  "トークン数はモデルごとに異なります。": "Token counts vary by model.",
  "実行方式": "Processing mode",
  "tok/sは入力トークン数÷入力処理時間です。モデル読込や画像・音声の準備は含みません。":
      "tok/s is input tokens divided by input processing time. Model loading and image/audio preparation are excluded.",
  "Totalは実行から結果が返るまでの時間です。撮影・録音や画面表示の時間は含みません。":
      "Total is the time from starting a run to receiving its result. Taking photos, recording and displaying the result are excluded.",
  "はじめての判定": "Your first decision",
  "例と判定条件が入ります。未取得のモデルはダウンロードしてください。":
      "This fills in an example and criteria. Download the model if needed.",
  "入力を用意する": "Add your input",
  "文章はサンプルのままでも、自分の文章でも試せます。写真・音声のタスクは入力を追加します。":
      "Use the sample text or your own. Add a photo or recording for image and audio tasks.",
  "選ばれた答え、候補の確率、処理速度を確認できます。指示や候補もタップして編集できます。":
      "See the answer, probabilities and speed. Tap instructions or options to edit them.",
  "このタスクのヒント": "Tips for this task",
  "写真：画像タスクを選び、カメラか写真ライブラリから追加。\n音声：音声タスクを選び、録音して「停止して使う」。最大30秒、omniで判定します。":
      "Photo: Choose an image task and add a photo from your camera or library.\nAudio: Choose an audio task, record, then tap Stop & use. Up to 30 seconds, using omni.",
  "候補を選ぶ：各候補の確率\nはい・いいえ：「はい」の確率\n段階で評価：各段階を0・1・2…とした平均評価\n\nTotal：実行から結果が返るまでの時間\nDecision：判定にかかった時間\nPrefill / Input speed：入力の処理速度（tok/s）\n\n確率は正解率ではありません。自分の例で結果を確かめてください。":
      "Choice: Probability for each option\nYes/no: Probability of Yes\nRating: Average rating with levels numbered 0, 1, 2…\n\nTotal: Time from starting a run to receiving its result\nDecision: Time spent on the decision\nPrefill / Input speed: Input processing speed (tok/s)\n\nProbability is not accuracy. Check the answers using your own examples.",
  "モデルを確認中": "Checking the model",
  "ファイルを確認中": "Checking the file",
  '表示言語': 'Language',
  '端末の言語': 'Device language',
  'モデルを取得して始める': 'Download a model to start',
  'サンプルタスク': 'Sample tasks',
  '入力の言語は表示言語と別に選べます': 'Sample language is independent of the interface',
  'モデルはアプリに含まれていません。Hugging Faceの公式配布元から取得します。':
      'Models are not bundled with the app. Download them from the official Hugging Face repositories.',
  '取得には通信と空き容量が必要です。途中で中止しても再開できます。':
      'Downloads need a network connection and free storage. You can cancel and resume them.',
  'このタスクに必要なモデルを取得': 'Download files for this task',
  '必要なデータ：{p0} · 約{p1} GB': 'Required files: {p0} · About {p1} GB',
  '画像用の追加データ {p0} MB': 'Additional image data {p0} MB',
  '画像・音声用の追加データ {p0} MB': 'Additional image/audio data {p0} MB',
  '使用容量：{p0} MB': 'Storage used: {p0} MB',
  'モデルファイルを削除': 'Delete model files',
  '{p0}を削除しますか？': 'Delete {p0}?',
  'モデル本体・追加データ・途中の取得ファイル（{p0} MB）を削除します。タスクと実行履歴は残ります。あとから再取得できます。':
      'Deletes the model, projector and partial downloads ({p0} MB). Your tasks and run history are kept. You can download the files again later.',
  '削除': 'Delete',
  "中止": "Cancel",
  "判定を実行する": "Run decision",
  "試す": "Try",
  "比較": "Compare",
  "履歴": "History",
  "モデル": "Models",
  "01  判定する写真": "01  Photo to evaluate",
  "01  判定する音声": "01  Audio to evaluate",
  "撮る、または写真から選ぶ": "Take a photo or choose one",
  "最大30秒 · omni": "Up to 30 seconds · omni",
  "01  判断する文章": "01  Text to evaluate",
  "入力の補足": "Input context",
  "サンプルのまま実行できます": "You can run the sample as it is",
  "写真・音声について伝えたいこと": "What to tell the model about your photo or audio",
  "判断したい文章を入力": "Enter the text to evaluate",
  "補足（任意）": "Additional context (optional)",
  "自分の文章に書き換えて、同じ条件で判定できます。":
      "Replace the sample with your own text and keep the same criteria.",
  "サンプルのままでも実行できます。": "You can also run this sample as it is.",
  "この例で確かめること": "What to check in this example",
  "02  モデルに聞くこと": "02  What to ask the model",
  "開くと指示・候補を編集できます": "Open to edit instructions and options",
  "もう1つ判定を追加": "Add another question",
  "この条件をタスクとして保存": "Save these criteria as a task",
  "03  写真・音声": "03  Photo or audio",
  "必要な時だけ追加": "Add only when needed",
  "使い方と結果の見方": "How to use and read results",
  "答え：はい / いいえ": "Answer: Yes / No",
  "候補：{p0}": "Options: {p0}",
  "低い順の {p0} 段階で評価": "Rate on {p0} levels, from low to high",
  "判定したいことを入力": "Enter what you want to decide",
  "質問 {p0}": "Question {p0}",
  "質問を削除": "Remove question",
  "候補を選ぶ": "Choose one",
  "はい・いいえ": "Yes / No",
  "段階で評価": "Rate",
  "用意した候補から1つを選び、各候補の確率を返します。":
      "Selects one option and returns the probability of every option.",
  "この指示に対する「はい」の確率を返します。":
      "Returns the probability of “Yes” for this instruction.",
  "低い順に並べた段階をもとに、0〜{p0}の範囲で評価します。":
      "Rates the input from 0 to {p0} using levels ordered from low to high.",
  "モデルに聞くこと": "What to ask the model",
  "例：この口コミの印象を選んでください。": "Example: Choose the sentiment of this review.",
  "タスクを選ぶ": "Choose a task",
  "用途を選ぶと、判定の指示・候補が入ります。":
      "Choose a use case to fill in instructions and options.",
  "画像": "Images",
  "音声": "Audio",
  "文章": "Text",
  "日本語のサンプル": "Japanese samples",
  "写真で試すサンプル": "Photo samples",
  "録音で試すサンプル": "Recording samples",
  "6つの用途を試す": "Try six use cases",
  "カメラ・写真に対応": "Camera and photo library",
  "d1-omniで判定": "Evaluate with d1-omni",
  "日本語": "Japanese",
  "自分のタスク": "My tasks",
  "文章や候補を変えたら、「この条件をタスクとして保存」でここに追加できます。":
      "Edit the text or options, then use “Save these criteria as a task” to add your task here.",
  "英語の比較用サンプル": "English comparison sample",
  "保存したタスクを削除": "Delete saved task",
  "自分のタスクとして保存": "Save as my task",
  "入力の補足・指示・候補を保存します。写真・音声は保存せず、次に使う時に選び直します。":
      "Saves the input context, instructions and options. Photos and audio are not included; choose them again when using the task.",
  "タスク名": "Task name",
  "登録先": "Category",
  "自動選択": "Automatic",
  "キャンセル": "Cancel",
  "保存": "Save",
  "タスクを保存しました。次はタスク一覧から選べます。":
      "Task saved. You can find it in the task list next time.",
  "同じ条件で、2モデルを比較": "Compare two models with the same input",
  "「試す」で編集中の入力を固定し、モデルを1つずつ読み込んで判定します。":
      "Uses the current input from Try and loads one model at a time to evaluate it.",
  "判断材料：{p0}": "Input: {p0}",
  "{p0}件の質問 · {p1} tokens · {p2}": "{p0} questions · {p1} tokens · {p2}",
  "音声入力はomni専用です。「試す」から実行してください。":
      "Audio input is available only with omni. Run it from Try.",
  "Totalは読込込み。判定時間と入力処理速度も並べて確認できます。":
      "Total includes loading. Compare decision time and input processing speed alongside it.",
  "両モデルで比較する": "Compare both models",
  "入力": "Input",
  "結果": "Results",
  "判断の結果": "Decision results",
  "確率とパフォーマンスを、ひと目で。": "Probabilities and performance at a glance.",
  "{p0}件の質問{p1}": "{p0} questions{p1}",
  " · 音声あり": " · with audio",
  " · 画像あり": " · with image",
  "候補の確率は、個別の判断が正しいことを保証する値ではありません。":
      "An option’s probability does not guarantee that this particular decision is correct.",
  "入力を編集する": "Edit input",
  "比較全体 {p0} {p1}": "Full comparison {p0} {p1}",
  "ファイルを読み込めませんでした。{p0}": "Could not read the file. {p0}",
  "実行記録 JSON": "Run record JSON",
  "JSONをコピーしました": "JSON copied",
  "コピー": "Copy",
  "実行記録を保存": "Save run record",
  "JSONを保存しました": "JSON saved",
  "実行履歴": "Run history",
  "入力、確率、モデルの版、実行環境を端末に保存します。":
      "Input, probabilities, model revision and runtime settings are saved on this device.",
  "最初の判定を実行すると、ここに記録されます。":
      "Your first decision will appear here after you run it.",
  "JSONを表示・保存": "View or save JSON",
  "履歴を削除": "Delete history entry",
  "モデルと実行環境": "Models and runtime",
  "モデルの取得後、推論はオフラインで動きます。":
      "Download the models once, then run inference offline.",
  "アプリの入力上限": "App input limit",
  "omniのテキスト確率を校正": "Calibrate omni text probabilities",
  "GGUFに含まれる質問種別・候補数ごとの温度を適用":
      "Apply the GGUF temperatures for each question type and option count",
  "Metalを選んだ場合、GPUに重みを配置できなければエラーを表示します。結果には実際の重み配置を記録します。":
      "Metal reports an error if model weights cannot be placed on the GPU. Results record the actual placement.",
  "{p0} · 本体 {p1} GB": "{p0} · Model {p1} GB",
  "画像・音声用プロジェクター {p0} MB": "Image/audio projector {p0} MB",
  "公式版 {p0} · LFM Open License v1.0":
      "Official revision {p0} · LFM Open License v1.0",
  "この版で検証すること": "What to explore in this version",
  "日本語・英語の分類、Yes/No、採点、候補や指示を変えた時の確率、モデル間の結果と速度、CPUとMetalの差。入力を自動で切り捨てず、上限を超えた場合は知らせます。":
      "Japanese and English classification, Yes/No and rating; probability changes when instructions or options change; model quality and speed; CPU versus Metal. Inputs are never silently truncated: exceeding the limit produces an error.",
  "メディア入力": "Media input",
  "カメラで撮影・写真から選択して、両モデルで画像判定を試せます。マイク録音はomniで判定します。画像と音声は同時に渡せません。":
      "Take a photo or choose one from your library to evaluate images with either model. Microphone recordings use omni. Images and audio cannot be combined in one request.",
  "画像は向きを補正し、長辺2048px以内で保存します。omniの画像・音声判定は実験用です。":
      "Images are saved with corrected orientation and a maximum long edge of 2048 px. Omni image and audio evaluation is experimental.",
  "モデル・ソフトウェアのライセンス": "Model and software licenses",
  "✓ 取得済み（実行前にSHA-256を確認）": "✓ Downloaded (SHA-256 is checked before each run)",
  "未取得": "Not downloaded",
  "再取得": "Download again",
  "取得・再開": "Download / resume",
  "GGUFを取り込む": "Import GGUF",
  "判断を、\n手のひらで。": "Decisions,\nin your hands.",
  "条件を変えて、確率と速さを確かめる。": "Change the criteria. Explore probabilities and speed.",
  "テキスト": "Text",
  "パフォーマンス比較": "Performance comparison",
  "判定": "Decision",
  "入力 tok/s": "Input tok/s",
  "入力のトークン数はモデルごとに異なります。tok/sは各モデルの入力処理速度です。":
      "Token counts differ between models. tok/s measures each model’s own input processing speed.",
  "実行環境未記録": "Runtime not recorded",
  "結果のJSON": "Result JSON",
  'モデルを保持して高速に再実行': 'Keep the model loaded for faster reruns',
  '同じモデルの再読込を省きます。メモリを使用し、アプリを離れると解放します。オフにすると毎回読み込みます。':
      'Skip reloading the same model. Uses memory and releases it when you leave the app. Turn off to reload every run.',
  'モデルの実行状態': 'Model execution state',
  '読み込み済みを再利用': 'Reusing the loaded model',
  'モデル読み込みあり': 'Includes model loading',
  'Totalは今回のファイル確認・必要な読込と解放・判定・受け渡しの合計です。モデル再利用時の読込は0 msですが、入力は毎回処理します。履歴保存と画面描画は含みません。メモリはアプリ全体の瞬間値です。':
      'Total includes this run’s file checks, any loading and unloading, evaluation and the app bridge. Loading is 0 ms when reusing the model; inputs are processed every time. History saving and rendering are excluded. Memory is a snapshot of the whole app.',
  'モデルを準備': 'Prepare model',
  'モデルを取得': 'Get model',
  '準備中…': 'Preparing…',
  '準備完了': 'Ready',
  '未準備': 'Not loaded',
  '解放': 'Unload',
  'モデルの準備が完了しました': 'Model preparation complete',
  'モデルをメモリから解放します。保存済みファイルは残ります。':
      'Release the model from memory. Downloaded files are kept.',
  '先に読み込んで待機します。準備するとモデルの保持をオンにします。':
      'Load the model in advance. Preparing also enables keeping it loaded.',
  '画像の長辺': 'Image long edge',
  '画像サイズ': 'Image size',
  '画像の長辺上限': 'Image long-edge limit',
  '縦横比を保って縮小します。小さい画像は拡大しません。':
      'Keeps the aspect ratio. Smaller images are not enlarged.',
  '判定する画像：{p0} × {p1} px': 'Input image: {p0} × {p1} px',
  '画像サイズを選び直してください': 'Choose a supported image size',
  '画像は向きを補正し、選んだ長辺サイズ以内で判定します。元画像は端末に保存し、サイズを変更すると作り直します。omniの画像・音声判定は実験用です。':
      'Images are orientation-corrected and kept within the selected long edge for evaluation. The source stays on your device and is used when changing the size. Omni image and audio evaluation is experimental.',
  "読込から解放まで": "From loading to unloading",
  "入力処理・ヘッド含む": "Including encoder and head",
  "入力の処理速度": "Input processing speed",
  "全質問の判定時間": "All questions combined",
  "全質問の入力合計": "Input across all questions",
  "「はい」 {p0}%": "Yes {p0}%",
  "評価 {p0} / {p1}": "Score {p0} / {p1}",
  "準備・その他": "Preparation / other",
  "メディア": "Media",
  "入力処理": "Forward",
  "計測の内訳": "Measurement breakdown",
  "ファイル確認": "File verification",
  "モデル読込": "Model loading",
  "入力の準備": "Input preparation",
  "画像・音声処理": "Image/audio processing",
  "入力処理＋判定ヘッド": "Encoder and decision head",
  "確率・結果の処理": "Probabilities and results",
  "モデル解放": "Model unloading",
  "その他・受け渡し": "Other / bridge overhead",
  "実入力の内訳": "Input token breakdown",
  "文字 {p0} / メディア {p1} tok": "Text {p0} / Media {p1} tok",
  "主モデルの重み配置": "Main model weight placement",
  "アプリのメモリ": "App memory",
  "{p0}全質問の入力トークン合計 ÷ GPU完了までのforward時間で計算。画像・音声の埋め込みも入力数に含み、メディアエンコードとモデル読込は分母に含みません。":
      "{p0}Calculated as total input tokens across all questions divided by forward time, including GPU completion. Media embeddings count as input; media encoding and model loading are excluded from the denominator.",
  "入力処理 tok/s はエンコーダーと判定ヘッドの処理量です。":
      "Input tok/s measures the encoder and decision head.",
  "Prefill tok/s は主モデルへの入力処理量です。":
      "Prefill tok/s measures the main model’s input processing.",
  "Totalはファイル確認・読込・判定・解放とアプリとの受け渡しを含みます。履歴保存と表示描画は含みません。各質問の入力を毎回処理します。メモリはアプリ全体の瞬間値です。":
      "Total includes file verification, loading, evaluation, unloading and the app bridge. History saving and rendering are excluded. Each question processes its input independently. Memory is a snapshot of the whole app.",
  "この履歴は旧版の記録です。Totalと入力速度は再実行で計測できます。":
      "This record is from an older version. Run it again to measure Total and input speed.",
  "「はい」の確率": "Probability of Yes",
  "評価段階の期待値 / {p0}": "Expected rating / {p0}",
  "選ばれた候補": "Selected option",
  "はい": "Yes",
  "いいえ": "No",
  "温度 {p0}": "Temperature {p0}",
  "判定条件をカスタマイズ中": "Customizing criteria",
  "選択中のタスク": "Current task",
  "使い方": "How to use",
  "① 写真を撮る・選ぶ → ② 判定を実行": "① Take / choose a photo → ② Run",
  "① 録音 → ② 停止して使う → ③ 実行": "① Record → ② Stop and use → ③ Run",
  "① タスクを選ぶ → ② 文章を変える → ③ 実行": "① Choose a task → ② Edit text → ③ Run",
  "まずは、日本語の例で試す": "Start with a sample task",
  "d1は、文章や画像・音声について、候補を選ぶ・はい／いいえで判断する・段階を評価するモデルです。指示と候補は、用途ごとに自由に変えられます。":
      "d1 selects an option, answers Yes/No or rates text, images and audio. Change the instructions and options for each use case.",
  "「口コミの印象」を選ぶ": "Choose “Review sentiment”",
  "サンプルの文章、聞くこと、3つの候補が自動で入ります。モデルは、まずd1-3Bを選んで試せます。":
      "The sample text, instruction and three options are filled in automatically. Start by trying d1-3B.",
  "判断したい文章を入れる": "Enter text to evaluate",
  "例：「料理がおいしく、また行きたいです」。自分の文章へ書き換えても構いません。":
      "Example: “The food was delicious. I would visit again.” You can replace it with your own text.",
  "「判定を実行する」を押す": "Tap “Run decision”",
  "「好意的・否定的・中立」のどれを選んだか、候補ごとの確率と処理速度が表示されます。":
      "See whether Positive, Negative or Neutral is selected, along with option probabilities and processing speed.",
  "条件を変えて、もう一度": "Change the criteria and try again",
  "「否定的な口コミ」に書き換える、候補を増やす、指示を変えるなどで結果の違いを確認できます。自分の条件は「この条件をタスクとして保存」で残せます。":
      "Try a negative review, add options or change the instruction to see how the result changes. Use “Save these criteria as a task” to keep your settings.",
  "写真・音声で試す": "Try photos and audio",
  "「タスクを選ぶ」の「画像」から「写真の主な色」などを選びます。「カメラで撮る」か「写真から選ぶ」で写真をセットし、判定を実行します。画像用のプロジェクターもモデル画面で取得してください。":
      "Choose Images in “Choose a task”, then select “Main photo color”. Use “Take a photo” or “Choose photo”, then run the decision. Download the image projector from Models too.",
  "「音声」から「声で操作を選ぶ」を選び、「マイクで録音」を押して話します。「停止して使う」の後、判定を実行します。モデルは自動でomniになります。最大30秒で自動停止し、アプリを離れた時も録音を停止します。":
      "Under Audio, choose “Voice controls”, tap “Record audio” and speak. Select “Stop and use”, then run. Omni is selected automatically. Recording stops at 30 seconds or when you leave the app.",
  "撮影・録音の時間は、判定結果のTotalには含みません。画像・音声のモデル処理時間は「計測の内訳」で確認できます。":
      "Time spent taking a photo or recording is excluded from Total. Find model media processing time in “Measurement breakdown”.",
  "3つの入力": "Three inputs",
  "判断する文章：モデルに読ませる内容\nモデルに聞くこと：何を判定してほしいか\n候補・評価段階：返してほしい答えと、その意味":
      "Text to evaluate: the content the model reads\nWhat to ask: the decision you want\nOptions / rating levels: possible answers and their meanings",
  "結果の見方": "Reading results",
  "候補から選ぶ：選択した候補と各候補の確率\nはい・いいえ：「はい」の確率\n段階で評価：低い順に0・1・2…とした評価の期待値\nTotal：実行全体の時間（必要なモデル読込を含む）\ntok/s：1秒あたりに処理した入力トークン数":
      "Choose one: the selected option and every option’s probability\nYes / No: the probability of Yes\nRate: the expected level, numbered 0, 1, 2… from low to high\nTotal: end-to-end processing time, including any model loading\ntok/s: input tokens processed per second",
  "モデルが未取得なら「モデル」タブで取得します。「比較」では同じ入力を両モデルに渡せます。確率の高さと正解かどうかは、自分の例でも確かめてください。":
      "Download missing models from Models. Compare sends the same input to both models. Check your own examples too: high probability does not guarantee a correct answer.",
  "試してみる": "Try it",
  "答えの候補": "Answer options",
  "評価の基準": "Rating criteria",
  "候補を1つ選びます": "Choose one option",
  "低い順に0・1・2…": "Low to high: 0, 1, 2…",
  "候補 {p0}": "Option {p0}",
  "段階 {p0}": "Level {p0}",
  "この候補を削除": "Remove this option",
  "候補の名前": "Option name",
  "この段階に当てはまる状態": "Condition for this level",
  "例：好意的": "Example: Positive",
  "例：一部の利用者に影響": "Example: Some users affected",
  "どんな時に選ぶか（任意）": "When to choose it (optional)",
  "例：満足や称賛": "Example: Satisfaction or praise",
  "候補を追加": "Add option",
  "評価段階を追加": "Add rating level",
  "{p0}秒 · マイク録音": "{p0} s · Microphone recording",
  "音声ファイル · 最大30秒": "Audio file · Up to 30 seconds",
  "録音中": "Recording",
  "マイクの入力音量": "Microphone input level",
  "停止して使う": "Stop and use",
  "録音を破棄": "Discard recording",
  "写真のプレビューを読み込めません": "Could not load the photo preview",
  "写真をセットしました": "Photo attached",
  "音声をセットしました": "Audio attached",
  "この写真で判定します": "This photo will be evaluated",
  "添付を解除": "Remove attachment",
  "見せたいものを、写真で": "Show it with a photo",
  "声を録音して、操作を判定": "Record your voice to choose a command",
  "カメラで撮る": "Take a photo",
  "写真から選ぶ": "Choose photo",
  "マイクで録音": "Record audio",
  "入力を準備しています…": "Preparing input…",
  "写真か音声を1件追加できます。音声はomniで判定します。":
      "Attach one photo or audio clip. Audio is evaluated with omni.",
  "撮影後に「写真を使用」を押すと、判定用の写真になります。":
      "After taking a photo, tap “Use Photo” to attach it for evaluation.",
  "最大30秒。停止すると判定用の音声になります。":
      "Up to 30 seconds. Stop recording to attach the audio for evaluation.",
  "ファイルから取り込む": "Import from a file",
  "画像ファイル": "Image file",
  "音声ファイル": "Audio file",
  "判定指示を入力してください": "Enter an instruction",
  "選択肢は重複しない名前で2〜26個にしてください":
      "Provide 2–26 options with unique, nonempty names",
  "評価段階を低い順に2〜10個入力してください":
      "Provide 2–10 rating levels ordered from low to high",
  "質問の種類が不正です": "Invalid question type",
  "判断材料を入力してください": "Enter input to evaluate",
  "質問を追加してください": "Add a question",
  "写真を撮るか、写真から選んでください": "Take a photo or choose one from your library",
  "マイクで録音してください": "Record audio with the microphone",
  "届いた商品が壊れていました。交換してもらえますか？":
      "The item arrived damaged. Could I get a replacement?",
  "問い合わせを分類": "Classify an inquiry",
  "この問い合わせは商品の交換を求めていますか？": "Is this inquiry requesting a replacement?",
  "タスク名を入力してください": "Enter a task name",
  "自分で保存した入力の補足と判定条件": "Input context and criteria you saved",
  "マイクを使うには、iPhoneの設定でD1 Labのマイクを許可してください。":
      "Allow D1 Lab to use the microphone in your device’s Settings.",
  "録音を保存できませんでした。": "Could not save the recording.",
  "カメラ・写真・マイクの使用が許可されていません。iPhoneの設定からD1 Labの権限を確認してください。":
      "Camera, photo or microphone access is not allowed. Check D1 Lab’s permissions in your device’s Settings.",
  "入力を取得できませんでした。{p0}": "Could not capture input. {p0}",
  "入力ファイルは50 MB以内にしてください": "Input files must be 50 MB or smaller",
  "取得を準備中": "Preparing download",
  "ダウンロードを中止しました": "Download cancelled",
  "取得・検証が完了しました": "Download and verification complete",
  "モデルファイルを削除中": "Deleting model files",
  "モデルファイルを削除しました": "Model files deleted",
  "中止を待っています…": "Waiting for cancellation…",
  "この版の推論はiOS・macOSに対応しています":
      "This version supports inference on iOS and macOS",
  "音声はomniで実行してください。3Bとの比較には対応していません":
      "Use omni for audio. Audio cannot be compared with 3B",
  "{p0}をモデル画面で取得してください": "Download {p0} from Models",
  "{p0}のプロジェクターをモデル画面で取得してください": "Download the {p0} projector from Models",
  "実行を中止しました": "Run cancelled",
  "{p0}：SHA-256を確認中": "{p0}: Checking SHA-256",
  "{p0}：{p1}で読み込み中": "{p0}: Loading with {p1}",
  "{p0}：判定中": "{p0}: Evaluating",
  "判定が完了しました": "Decision complete",
  "履歴から読み込んだタスク": "Task loaded from history",
  "モデルが未取得、または容量が一致しません": "The model is missing or its size does not match",
  "SHA-256が一致しません。モデルを再取得してください": "SHA-256 mismatch. Download the model again",
  "取得失敗: HTTP {p0}": "Download failed: HTTP {p0}",
  '配布版の変更に合わせて取得をやり直しています': 'Restarting download for the updated release',
  '配布先へのアクセスが拒否されました（HTTP 403）。時間をおいて再試行してください。公式GGUFのファイル取り込みも使えます。':
      'The download server denied access (HTTP 403). Try again later. You can also import the official GGUF files.',
  "再開位置が一致しません": "The resume position does not match",
  "配布ファイル容量が一致しません": "The downloaded file size does not match",
  "取得が途中で終了しました。再開できます": "The download ended early. You can resume it",
  "SHA-256を検証中": "Verifying SHA-256",
  "SHA-256が一致しません": "SHA-256 mismatch",
  "この配布モデルとファイル容量が一致しません": "File size does not match this model release",
  "指定の公式GGUFとSHA-256が一致しません":
      "SHA-256 does not match the specified official GGUF",
  "録音データを読み込めません。もう一度録音してください。":
      "Could not read the recording. Please record again.",
  "録音はPCM WAV形式で行ってください。": "Record audio in PCM WAV format.",
  "音声が録音されていません。もう一度録音してください。":
      "The recording has no audio. Please record again.",
  "画像を読み込めませんでした": "Could not read the image",
  "結果のメモリを確保できませんでした": "Could not allocate memory for the result",
};
