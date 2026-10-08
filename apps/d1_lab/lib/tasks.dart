import 'domain.dart';

class TaskQuestion {
  const TaskQuestion(this.type, this.instructions, [this.criteria = '']);
  final String type, instructions, criteria;
  Map<String, dynamic> toJson() => {
    'type': type,
    'instructions': instructions,
    'criteria': criteria,
  };
  factory TaskQuestion.fromJson(Map<String, dynamic> j) =>
      TaskQuestion(j['type'], j['instructions'], j['criteria'] ?? '');
}

class D1Task {
  const D1Task({
    required this.id,
    required this.title,
    required this.description,
    required this.state,
    required this.questions,
    this.check = '',
    this.language = '日本語',
    this.inputKind = 'text',
  });
  final String id, title, description, state, check, language;
  final String inputKind;
  final List<TaskQuestion> questions;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'state': state,
    'questions': questions.map((q) => q.toJson()).toList(),
    'check': check,
    'language': language,
    'inputKind': inputKind,
  };
  factory D1Task.fromJson(Map<String, dynamic> j) {
    final task = D1Task(
      id: j['id'],
      title: j['title'],
      description: j['description'],
      state: j['state'],
      check: j['check'] ?? '',
      language: j['language'] ?? '自分のタスク',
      inputKind: j['inputKind'] ?? 'text',
      questions: (j['questions'] as List)
          .map((q) => TaskQuestion.fromJson(Map<String, dynamic>.from(q)))
          .toList(),
    );
    task.validate();
    return task;
  }
  void validate() {
    if (!['text', 'image', 'audio'].contains(inputKind)) {
      throw const FormatException('入力の種類が不正です');
    }
    snapshot(
      state,
      [
        for (final (i, q) in questions.indexed)
          Question(
            id: '$i',
            type: q.type,
            instructions: q.instructions,
            criteria: q.criteria,
          ),
      ],
      true,
      allowEmptyState: inputKind != 'text',
    );
  }
}

const builtinTasks = [
  D1Task(
    id: 'inquiry-jp',
    title: '問い合わせを分類',
    description: '届いた問い合わせを、担当ごとに振り分けます。',
    state: '届いた商品が壊れていました。交換してもらえますか？',
    questions: [
      TaskQuestion(
        'choice',
        'この問い合わせの担当を選んでください。',
        '配送|配達と追跡\n返品交換|破損と返品\n支払い|請求と決済\nその他|該当なし',
      ),
    ],
    check: 'この例では「返品交換」が選ばれるか確認します。「荷物はいつ届きますか？」に変えて、結果の変化も試せます。',
  ),
  D1Task(
    id: 'review-jp',
    title: '口コミの印象',
    description: '口コミが好意的か、否定的かを選びます。',
    state: '料理がおいしく、店員さんも親切でした。また行きたいです。',
    questions: [
      TaskQuestion(
        'choice',
        'この口コミの印象を選んでください。',
        '好意的|満足や称賛\n否定的|不満や批判\n中立|どちらでもない',
      ),
    ],
    check: 'この例では「好意的」が選ばれるか確認します。「料理が冷たく、長く待たされた」に変えるとどうなるでしょう。',
  ),
  D1Task(
    id: 'memo-jp',
    title: 'メモの保存先',
    description: 'メモを仕事・買い物・予定に分類します。',
    state: 'スーパーで卵、牛乳、食パンを買う。',
    questions: [
      TaskQuestion(
        'choice',
        'このメモの保存先を選んでください。',
        '仕事|業務の記録\n買い物|購入の予定\n予定|日時の約束\nその他|該当なし',
      ),
    ],
    check: 'この例では「買い物」が選ばれるか確認します。自分のメモや、自分で決めた保存先でも試せます。',
  ),
  D1Task(
    id: 'refund-jp',
    title: '返金の希望を確認',
    description: '返金を求めているか、はい・いいえで判定します。',
    state: '二重に請求されていました。余分に支払った分を返してください。',
    questions: [TaskQuestion('noul', 'この文章は返金を求めていますか？')],
    check: 'この例では「はい」の確率が高くなるか確認します。「請求の内訳を教えてください」との違いも試せます。',
  ),
  D1Task(
    id: 'urgency-jp',
    title: '対応の緊急度',
    description: '影響の大きさを、低い順の3段階で評価します。',
    state: '本番システムでログインできません。すべてのお客様が影響を受けています。',
    questions: [
      TaskQuestion(
        'score',
        '対応の緊急度を評価してください。',
        '通常の問い合わせ\n一部の利用者に影響\n全利用者が利用不能',
      ),
    ],
    check: 'この例では、最も高い段階の「2」に近い値になるか確認します。基準を変えると、評価の意味も変わります。',
  ),
  D1Task(
    id: 'relevance-jp',
    title: '役立つ資料を選別',
    description: '資料が、知りたいことの回答に役立つかを判定します。',
    state: 'この資料では、パスワードの再設定とアカウントへのアクセスを復旧する方法を説明しています。',
    questions: [TaskQuestion('noul', 'この資料はパスワードを忘れた人の役に立ちますか？')],
    check: 'この例では「はい」の確率が高くなるか確認します。無関係な資料に差し替えて比べられます。',
  ),
  D1Task(
    id: 'inquiry-en',
    title: 'Inquiry with two questions',
    language: '英語',
    description: 'Route an inquiry and check for a replacement request.',
    state: 'The package arrived damaged. Can I get a replacement?',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the department for this request.',
        'Shipping|Delivery and tracking\nReturns|Damage and replacement\nBilling|Payments\nOther|None of the above',
      ),
      TaskQuestion('noul', 'Does the customer request a replacement?'),
    ],
    check:
        'Check whether Returns is selected and the probability of Yes for requesting a replacement is high.',
  ),
  D1Task(
    id: 'image-color-jp',
    title: '写真の主な色',
    inputKind: 'image',
    description: '色のついた物を撮って、主な色を選びます。',
    state: '添付した写真の中央にある物を見てください。',
    questions: [
      TaskQuestion('choice', '中央の物の主な色を選んでください。', '赤|赤系\n緑|緑系\n青|青系\nその他|上記以外'),
    ],
    check: '赤いマグカップなどを撮影して、見た目に合う色を選ぶか確認します。背景をシンプルにして、別の色でも比べてみましょう。',
  ),
  D1Task(
    id: 'image-object-jp',
    title: '写っている物を分類',
    inputKind: 'image',
    description: '食べ物・動物・日用品のどれが写っているかを選びます。',
    state: '添付した写真の主な被写体を見てください。',
    questions: [
      TaskQuestion(
        'choice',
        '主な被写体の種類を選んでください。',
        '食べ物|食材や料理\n動物|犬や猫など\n日用品|生活で使う物\nその他|上記以外',
      ),
    ],
    check: '料理やマグカップなど、1つの物を大きく撮って試します。複数の物が写った場合も、主な被写体を選べるか確認できます。',
  ),
  D1Task(
    id: 'image-document-jp',
    title: '書類の種類を判定',
    inputKind: 'image',
    description: 'レシート・文書・その他を画像から選びます。',
    state: '添付した画像の全体を見てください。',
    questions: [
      TaskQuestion(
        'choice',
        '画像に写っているものの種類を選んでください。',
        'レシート|購入明細と合計金額\n文書|文章を中心とした紙\nその他|書類以外',
      ),
    ],
    check: 'レシート全体が入るように撮影します。文字を読み取って一覧にするタスクではなく、書類の種類を選ぶタスクです。',
  ),
  D1Task(
    id: 'image-cup-jp',
    title: 'カップが写っている？',
    inputKind: 'image',
    description: '写真にカップがあるか、はい・いいえで判定します。',
    state: '添付した写真を見てください。',
    questions: [TaskQuestion('noul', 'この写真にコップやマグカップが写っていますか？')],
    check: 'カップがある写真と、ない写真で「はい」の確率を比べます。指示を「鍵が写っていますか？」などに変えても試せます。',
  ),
  D1Task(
    id: 'audio-command-jp',
    title: '声で操作を選ぶ',
    inputKind: 'audio',
    description: '録音した声から、再生・停止・音量変更を選びます。',
    state: '',
    questions: [
      TaskQuestion(
        'choice',
        '話した人が求めている操作を選んでください。',
        '再生|音楽を再生\n停止|音楽を止める\n音量変更|音量を変える\nその他|該当なし',
      ),
    ],
    check:
        '「音楽を止めて」と録音し、「停止」を選ぶか確認します。補足文は不要です。音声は英語で学習されているため、日本語の精度も確認してください。',
  ),
];

const englishTasks = [
  D1Task(
    id: 'inquiry-en-start',
    title: 'Classify an inquiry',
    language: '英語',
    description: 'Route a customer request to the right department.',
    state: 'The item arrived damaged. Could I get a replacement?',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the department for this request.',
        'Shipping|Delivery and tracking\nReturns|Damage and replacement\nBilling|Payments\nOther|None of the above',
      ),
    ],
    check:
        'Check whether Returns is selected. Change the text to “When will my package arrive?” and compare the result.',
  ),
  D1Task(
    id: 'review-en',
    title: 'Review sentiment',
    language: '英語',
    description: 'Choose whether a review is positive, negative or neutral.',
    state:
        'The food was delicious and the staff were kind. I would visit again.',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the sentiment of this review.',
        'Positive|Satisfaction or praise\nNegative|Dissatisfaction or criticism\nNeutral|Neither positive nor negative',
      ),
    ],
    check:
        'Check whether Positive is selected. Try “The food was cold and we waited too long” next.',
  ),
  D1Task(
    id: 'memo-en',
    title: 'Organize a note',
    language: '英語',
    description: 'Classify a note as work, shopping or a calendar event.',
    state: 'Buy eggs, milk and bread at the supermarket.',
    questions: [
      TaskQuestion(
        'choice',
        'Choose where to save this note.',
        'Work|Business notes\nShopping|Purchases to make\nCalendar|Appointments with a date or time\nOther|None of the above',
      ),
    ],
    check:
        'Check whether Shopping is selected. Try your own notes and categories.',
  ),
  D1Task(
    id: 'refund-en',
    title: 'Check a refund request',
    language: '英語',
    description: 'Determine whether a customer is requesting a refund.',
    state: 'I was charged twice. Please refund the extra payment.',
    questions: [TaskQuestion('noul', 'Is this message requesting a refund?')],
    check:
        'Check for a high probability of Yes. Compare with “Can you explain the charges?”',
  ),
  D1Task(
    id: 'urgency-en',
    title: 'Rate urgency',
    language: '英語',
    description: 'Rate urgency using three levels of impact.',
    state: 'The service is down and no users can log in.',
    questions: [
      TaskQuestion(
        'score',
        'Rate the urgency of responding to this issue.',
        'Routine inquiry\nSome users affected\nAll users unable to use the service',
      ),
    ],
    check:
        'Check whether the score is near the highest level, 2. Changing the levels changes what the score means.',
  ),
  D1Task(
    id: 'relevance-en',
    title: 'Select useful documents',
    language: '英語',
    description: 'Check whether a document helps answer a question.',
    state:
        'This document explains how to reset a password and recover access to an account.',
    questions: [
      TaskQuestion(
        'noul',
        'Does this document help someone who forgot their password?',
      ),
    ],
    check:
        'Check for a high probability of Yes. Replace the document with unrelated content and compare.',
  ),
  D1Task(
    id: 'image-color-en',
    title: 'Main photo color',
    language: '英語',
    inputKind: 'image',
    description: 'Photograph a colored object and choose its main color.',
    state: 'Look at the object in the center of the attached photo.',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the main color of the central object.',
        'Red|Red shades\nGreen|Green shades\nBlue|Blue shades\nOther|None of the above',
      ),
    ],
    check:
        'Photograph a red mug and check whether its color is selected. Use a simple background, then try another color.',
  ),
  D1Task(
    id: 'image-object-en',
    title: 'Classify the subject',
    language: '英語',
    inputKind: 'image',
    description: 'Choose food, animal or household item from a photo.',
    state: 'Look at the main subject of the attached photo.',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the type of the main subject.',
        'Food|Ingredients or meals\nAnimal|Dogs, cats or other animals\nHousehold item|Everyday objects\nOther|None of the above',
      ),
    ],
    check:
        'Take a close-up photo of a meal or mug. Try multiple objects to see which subject is selected.',
  ),
  D1Task(
    id: 'image-document-en',
    title: 'Document type',
    language: '英語',
    inputKind: 'image',
    description: 'Choose receipt, document or other from an image.',
    state: 'Look at the whole attached image.',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the type of item shown in the image.',
        'Receipt|Purchase items and a total amount\nDocument|A page containing mainly text\nOther|Not a document',
      ),
    ],
    check:
        'Include the whole receipt in your photo. This task classifies the document; it does not transcribe its contents.',
  ),
  D1Task(
    id: 'image-cup-en',
    title: 'Is there a cup?',
    language: '英語',
    inputKind: 'image',
    description: 'Check whether a cup is present in a photo.',
    state: 'Look at the attached photo.',
    questions: [
      TaskQuestion('noul', 'Is there a drinking cup or mug in this photo?'),
    ],
    check:
        'Compare the probability of Yes with and without a cup. Change the instruction to ask about keys or another object.',
  ),
  D1Task(
    id: 'audio-command-en',
    title: 'Voice controls',
    language: '英語',
    inputKind: 'audio',
    description: 'Choose play, stop or volume change from a recording.',
    state: '',
    questions: [
      TaskQuestion(
        'choice',
        'Choose the action the speaker is requesting.',
        'Play|Play music\nStop|Stop music\nChange volume|Adjust volume\nOther|None of the above',
      ),
    ],
    check:
        'Record “Stop the music” and check whether Stop is selected. No additional text is needed. Audio evaluation is experimental and trained on English speech.',
  ),
];

const allBuiltinTasks = [...englishTasks, ...builtinTasks];
