import 'package:flutter/material.dart';
import 'design.dart';
import 'l10n/strings.dart';
import 'performance.dart';

class ComparisonOverview extends StatelessWidget {
  const ComparisonOverview({super.key, required this.entry});
  final Map<String, dynamic> entry;
  @override
  Widget build(BuildContext context) {
    final runs = (entry['runs'] as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    return Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(context.strings.text("パフォーマンス比較")),
            Table(
              columnWidths: {0: FlexColumnWidth(.85)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    SizedBox(),
                    for (final r in runs)
                      Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          r['model'] == 'd1-3B' ? 'd1-3B' : 'omni 600M',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final pair in [
                  ('Total', 'endToEndMs'),
                  (context.strings.text("判定"), 'totalMs'),
                  (context.strings.text("入力 tok/s"), 'inputTokPerSec'),
                ])
                  TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          pair.$1,
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                      for (final r in runs)
                        Text(
                          pair.$2 == 'inputTokPerSec'
                              ? metricNumber(metric(r, pair.$2), decimals: 0)
                              : '${durationMetric(metric(r, pair.$2)).value} ${durationMetric(metric(r, pair.$2)).unit}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              context.strings.text("トークン数はモデルごとに異なります。"),
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class RunResults extends StatelessWidget {
  const RunResults({
    super.key,
    required this.run,
    required this.onJson,
    this.imageInfo,
  });
  final Map<String, dynamic> run;
  final Map<String, dynamic>? imageInfo;
  final VoidCallback onJson;
  @override
  Widget build(BuildContext context) {
    final omni = run['model'] == 'd1-omni-600M';
    final total = durationMetric(metric(run, 'endToEndMs'));
    final inference = durationMetric(metric(run, 'totalMs'));
    final placement = run['placement'] as Map? ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        omni ? Icons.graphic_eq : Icons.view_in_ar_outlined,
                        color: teal,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${run['model']}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          Text(
                            '${run['quantization'] ?? ''}  ·  ${placement['actual'] ?? context.strings.text("実行環境未記録")}',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onJson,
                      tooltip: context.strings.text("結果のJSON"),
                      icon: Icon(Icons.ios_share, size: 19),
                    ),
                  ],
                ),
                SizedBox(height: 22),
                if ((run['results'] as List).isNotEmpty) ...[
                  _AnswerPreview(
                    Map<String, dynamic>.from((run['results'] as List).first),
                  ),
                  SizedBox(height: 16),
                ],
                LayoutBuilder(
                  builder: (context, c) {
                    final width = (c.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        MetricTile(
                          width: width,
                          label: 'TOTAL',
                          value: total.value,
                          unit: total.unit,
                          subtitle: context.strings.text(
                            run['runtimeReused'] == true
                                ? '読み込み済みを再利用'
                                : run.containsKey('runtimeReused')
                                ? 'モデル読み込みあり'
                                : '読込から解放まで',
                          ),
                          primary: true,
                        ),
                        MetricTile(
                          width: width,
                          label: omni ? 'INPUT SPEED' : 'PREFILL',
                          value: metricNumber(
                            metric(run, 'inputTokPerSec'),
                            decimals: 0,
                          ),
                          unit: 'tok/s',
                          subtitle: context.strings.text("入力の処理速度"),
                        ),
                        MetricTile(
                          width: width,
                          label: 'DECISION',
                          value: inference.value,
                          unit: inference.unit,
                          subtitle: context.strings.text("全質問の判定時間"),
                        ),
                        MetricTile(
                          width: width,
                          label: 'INPUT TOKENS',
                          value: metricNumber(
                            metric(run, 'inputTokens'),
                            decimals: 0,
                          ),
                          unit: 'tok',
                          subtitle: context.strings.text("全質問の入力合計"),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 18),
                _Timeline(run),
                SizedBox(height: 8),
                _TimingDetails(run, omni: omni, imageInfo: imageInfo),
              ],
            ),
          ),
        ),
        for (final (index, value) in (run['results'] as List).indexed)
          _QuestionResult(
            Map<String, dynamic>.from(value),
            index: index,
            omni: omni,
          ),
      ],
    );
  }
}

class _AnswerPreview extends StatelessWidget {
  const _AnswerPreview(this.result);
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) {
    final answer = result['type'] == 'noul'
        ? context.strings.text("「はい」 {p0}%", {
            'p0': ((result['yesProbability'] as num) * 100).toStringAsFixed(1),
          })
        : result['type'] == 'score'
        ? context.strings.text("評価 {p0} / {p1}", {
            'p0': (result['score'] as num).toStringAsFixed(2),
            'p1': (result['probabilities'] as List).length - 1,
          })
        : '${result['selected']}';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color(0xffeaf3e9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result['instructions']}',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          SizedBox(height: 6),
          Text(
            answer,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: teal,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.width,
    required this.label,
    required this.value,
    required this.unit,
    required this.subtitle,
    this.primary = false,
  });
  final double width;
  final String label, value, unit, subtitle;
  final bool primary;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
    decoration: BoxDecoration(
      color: primary ? ink : canvas,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: primary ? mint : muted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        SizedBox(height: 9),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: primary ? Colors.white : ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(color: primary ? mint : muted, fontSize: 10),
              ),
            ],
          ),
        ),
        SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: primary ? Colors.white.withValues(alpha: .65) : muted,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.run);
  final Map<String, dynamic> run;
  @override
  Widget build(BuildContext context) {
    final total = metric(run, 'endToEndMs');
    final forward = metric(run, 'forwardMs');
    if (total == null || forward == null || total <= 0) {
      return SizedBox.shrink();
    }
    final media = metric(run, 'mediaEncodeMs') ?? 0;
    final parts = [
      (
        name: context.strings.text("準備・その他"),
        value: (total - forward - media).clamp(0.0, total),
        color: line,
      ),
      if (media > 0)
        (
          name: context.strings.text("メディア"),
          value: media,
          color: Color(0xffe5bb79),
        ),
      (name: context.strings.text("入力処理"), value: forward, color: teal),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              for (final p in parts)
                if (p.value > 0)
                  Expanded(
                    flex: (p.value / total * 10000).round().clamp(1, 10000),
                    child: Container(height: 7, color: p.color),
                  ),
            ],
          ),
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: p.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      p.name,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _TimingDetails extends StatelessWidget {
  const _TimingDetails(this.run, {required this.omni, this.imageInfo});
  final Map<String, dynamic> run;
  final bool omni;
  final Map<String, dynamic>? imageInfo;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.only(bottom: 6),
      title: Text(
        context.strings.text("計測の内訳"),
        style: TextStyle(
          fontSize: 12,
          color: teal,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        if (imageInfo?['width'] != null && imageInfo?['height'] != null)
          _DetailRow(
            context.strings.text('画像サイズ'),
            '${imageInfo!['width']} × ${imageInfo!['height']} px',
          ),
        if (imageInfo?['maxPixelSize'] != null)
          _DetailRow(
            context.strings.text('画像の長辺上限'),
            '${imageInfo!['maxPixelSize']} px',
          ),
        if (run.containsKey('runtimeReused'))
          _DetailRow(
            context.strings.text('モデルの実行状態'),
            context.strings.text(
              run['runtimeReused'] == true ? '読み込み済みを再利用' : 'モデル読み込みあり',
            ),
          ),
        for (final pair in [
          (context.strings.text("ファイル確認"), 'verifyMs'),
          (context.strings.text("モデル読込"), 'loadCallMs'),
          (context.strings.text("入力の準備"), 'inputPrepareMs'),
          (context.strings.text("画像・音声処理"), 'mediaEncodeMs'),
          (omni ? context.strings.text("入力処理") : 'Prefill', 'forwardMs'),
          (context.strings.text("確率・結果の処理"), 'postprocessMs'),
          (context.strings.text("モデル解放"), 'unloadMs'),
        ])
          _DetailRow(pair.$1, '${metricNumber(metric(run, pair.$2))} ms'),
        _DetailRow(
          context.strings.text("その他・受け渡し"),
          '${metricNumber(timingOverhead(run))} ms',
        ),
        _DetailRow(
          context.strings.text("実入力の内訳"),
          context.strings.text("文字 {p0} / メディア {p1} tok", {
            'p0': metricNumber(metric(run, 'textTokens'), decimals: 0),
            'p1': metricNumber(metric(run, 'mediaTokens'), decimals: 0),
          }),
        ),
        _DetailRow(
          context.strings.text("実行方式"),
          '${run['placement']?['actual'] ?? '—'}',
        ),
        _DetailRow(
          context.strings.text("アプリのメモリ"),
          '${metricNumber(metric(Map<String, dynamic>.from(run['processMemory'] ?? {}), 'physicalFootprintMB'))} MiB',
        ),
        SizedBox(height: 10),
        Text(
          context.strings.text("tok/sは入力トークン数÷入力処理時間です。モデル読込や画像・音声の準備は含みません。"),
          style: TextStyle(color: muted, fontSize: 11, height: 1.6),
        ),
        SizedBox(height: 8),
        Text(
          context.strings.text('Totalは実行から結果が返るまでの時間です。撮影・録音や画面表示の時間は含みません。'),
          style: TextStyle(color: muted, fontSize: 11, height: 1.6),
        ),
        if (run['endToEndMs'] == null)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              context.strings.text("この履歴は旧版の記録です。Totalと入力速度は再実行で計測できます。"),
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 11, color: muted)),
        ),
        SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

class _QuestionResult extends StatelessWidget {
  const _QuestionResult(this.result, {required this.index, required this.omni});
  final Map<String, dynamic> result;
  final int index;
  final bool omni;
  @override
  Widget build(BuildContext context) {
    final type = result['type'];
    final probs = result['probabilities'] as List;
    final answer = type == 'noul'
        ? '${((result['yesProbability'] as num) * 100).toStringAsFixed(1)}%'
        : type == 'score'
        ? (result['score'] as num).toStringAsFixed(2)
        : '${result['selected']}';
    return Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LabBadge('QUESTION ${index + 1}'),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    type == 'noul'
                        ? context.strings.text("はい・いいえ")
                        : type == 'score'
                        ? context.strings.text("段階で評価")
                        : context.strings.text("候補を選ぶ"),
                    style: TextStyle(
                      fontSize: 10,
                      color: muted,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              '${result['instructions']}',
              style: TextStyle(fontSize: 13, color: ink, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              type == 'noul'
                  ? context.strings.text("「はい」の確率")
                  : type == 'score'
                  ? context.strings.text("評価段階の期待値 / {p0}", {
                      'p0': probs.length - 1,
                    })
                  : context.strings.text("選ばれた候補"),
              style: TextStyle(fontSize: 10, color: muted),
            ),
            SizedBox(height: 4),
            Text(
              answer,
              style: TextStyle(
                fontSize: 30,
                color: teal,
                fontWeight: FontWeight.w700,
                letterSpacing: -.7,
              ),
            ),
            SizedBox(height: 18),
            for (final p in probs)
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${type == 'noul'
                                ? p['label'] == 'Yes'
                                      ? context.strings.text("はい")
                                      : context.strings.text("いいえ")
                                : p['label']}${type == 'score' ? ' · ${p['description']}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: p['label'] == result['selected']
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '${((p['probability'] as num) * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: (p['probability'] as num).toDouble(),
                      minHeight: 5,
                      color: p['label'] == result['selected'] ? teal : mint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ),
            Divider(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                Text(
                  '${result['tokens']} tok',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                Text(
                  '${metricNumber(metric(result, 'inferenceMs'))} ms',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                Text(
                  '${omni ? context.strings.text("入力") : 'Prefill'} ${metricNumber(metric(result, 'inputTokPerSec'), decimals: 0)} tok/s',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
