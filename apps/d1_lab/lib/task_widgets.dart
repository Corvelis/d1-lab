import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'l10n/strings.dart';
import 'domain.dart';

class TaskIntro extends StatelessWidget {
  const TaskIntro({
    super.key,
    required this.title,
    required this.modified,
    required this.onChoose,
    required this.onHelp,
  });
  final String title;
  final bool modified;
  final VoidCallback? onChoose;
  final VoidCallback onHelp;
  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: 20),
    padding: EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                modified
                    ? context.strings.text("編集したタスク")
                    : context.strings.text("選択中のタスク"),
                style: TextStyle(color: mint, fontSize: 11),
              ),
            ),
            TextButton.icon(
              onPressed: onHelp,
              style: TextButton.styleFrom(
                foregroundColor: mint,
                padding: EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: Icon(Icons.help_outline_rounded, size: 16),
              label: Text(
                context.strings.text("使い方"),
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        SizedBox(height: 14),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: .25)),
          ),
          onPressed: onChoose,
          icon: Icon(Icons.grid_view_rounded, size: 16),
          label: Text(
            context.strings.text("タスクを選ぶ"),
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class UsageGuide extends StatelessWidget {
  const UsageGuide({super.key, this.taskHint = ''});
  final String taskHint;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(24),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.text('はじめての判定'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 20),
          _GuideStep(
            '1',
            context.strings.text('タスクを選ぶ'),
            context.strings.text('例と判定条件が入ります。未取得のモデルはダウンロードしてください。'),
          ),
          _GuideStep(
            '2',
            context.strings.text('入力を用意する'),
            context.strings.text(
              '文章はサンプルのままでも、自分の文章でも試せます。写真・音声のタスクは入力を追加します。',
            ),
          ),
          _GuideStep(
            '3',
            context.strings.text('「判定を実行する」を押す'),
            context.strings.text('選ばれた答え、候補の確率、処理速度を確認できます。指示や候補もタップして編集できます。'),
          ),
          if (taskHint.isNotEmpty)
            _GuideSection(
              title: context.strings.text('このタスクのヒント'),
              text: taskHint,
            ),
          _GuideSection(
            title: context.strings.text('写真・音声で試す'),
            text: context.strings.text(
              '写真：画像タスクを選び、カメラか写真ライブラリから追加。\n音声：音声タスクを選び、録音して「停止して使う」。最大30秒、omniで判定します。',
            ),
          ),
          _GuideSection(
            title: context.strings.text('結果の見方'),
            text: context.strings.text(
              '候補を選ぶ：各候補の確率\nはい・いいえ：「はい」の確率\n段階で評価：各段階を0・1・2…とした平均評価\n\nTotal：実行から結果が返るまでの時間\nDecision：判定にかかった時間\nPrefill / Input speed：入力の処理速度（tok/s）\n\n確率は正解率ではありません。自分の例で結果を確かめてください。',
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.strings.text('試してみる')),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.text});
  final String title, text;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.only(bottom: 16),
    title: Text(
      title,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: muted, fontSize: 12, height: 1.6),
        ),
      ),
    ],
  );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep(this.number, this.title, this.body);
  final String number, title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: mint,
          child: Text(
            number,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(color: muted, fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Structured candidate fields avoid exposing the runtime's pipe-separated format.
class CriteriaEditor extends StatefulWidget {
  const CriteriaEditor({
    super.key,
    required this.question,
    required this.enabled,
    required this.onChanged,
  });
  final Question question;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  State<CriteriaEditor> createState() => _CriteriaEditorState();
}

class _Criterion {
  _Criterion(this.id, String name, String description)
    : name = TextEditingController(text: name),
      description = TextEditingController(text: description);
  final int id;
  final TextEditingController name, description;
  void dispose() {
    name.dispose();
    description.dispose();
  }
}

class _CriteriaEditorState extends State<CriteriaEditor> {
  final rows = <_Criterion>[];
  int nextId = 0;
  late String kind;
  @override
  void initState() {
    super.initState();
    read();
  }

  void read() {
    kind = widget.question.type;
    for (final line
        in widget.question.criteria
            .split('\n')
            .where((s) => s.trim().isNotEmpty)) {
      final at = kind == 'choice' ? line.indexOf('|') : -1;
      rows.add(
        _Criterion(
          nextId++,
          at < 0 ? line : line.substring(0, at),
          at < 0 ? '' : line.substring(at + 1),
        ),
      );
    }
    while (rows.length < 2) {
      rows.add(_Criterion(nextId++, '', ''));
    }
  }

  @override
  void didUpdateWidget(CriteriaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id ||
        kind != widget.question.type) {
      for (final row in rows) {
        row.dispose();
      }
      rows.clear();
      read();
    }
  }

  void flush() {
    widget.question.criteria = rows
        .map(
          (r) => kind == 'choice'
              ? '${r.name.text}|${r.description.text}'
              : r.name.text,
        )
        .join('\n');
    widget.onChanged();
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionLabel(
        kind == 'choice'
            ? context.strings.text("答えの候補")
            : context.strings.text("評価の基準"),
        caption: kind == 'choice'
            ? context.strings.text("候補を1つ選びます")
            : context.strings.text("低い順に0・1・2…"),
      ),
      for (final (i, row) in rows.indexed)
        Container(
          key: ValueKey(row.id),
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: canvas,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    kind == 'choice'
                        ? context.strings.text("候補 {p0}", {'p0': i + 1})
                        : context.strings.text("段階 {p0}", {'p0': i}),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    tooltip: context.strings.text("この候補を削除"),
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.close, size: 16),
                    onPressed: !widget.enabled || rows.length <= 2
                        ? null
                        : () {
                            setState(() {
                              rows.remove(row);
                            });
                            flush();
                            row.dispose();
                          },
                  ),
                ],
              ),
              TextField(
                controller: row.name,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText: kind == 'choice'
                      ? context.strings.text("候補の名前")
                      : context.strings.text("この段階に当てはまる状態"),
                  hintText: kind == 'choice'
                      ? context.strings.text("例：好意的")
                      : context.strings.text("例：一部の利用者に影響"),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(
                    RegExp(kind == 'choice' ? r'[\r\n|]' : r'[\r\n]'),
                  ),
                ],
                onChanged: (_) => flush(),
              ),
              if (kind == 'choice') ...[
                SizedBox(height: 8),
                TextField(
                  controller: row.description,
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    labelText: context.strings.text("どんな時に選ぶか（任意）"),
                    hintText: context.strings.text("例：満足や称賛"),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                  ],
                  onChanged: (_) => flush(),
                ),
              ],
            ],
          ),
        ),
      TextButton.icon(
        onPressed:
            !widget.enabled || rows.length >= (kind == 'choice' ? 26 : 10)
            ? null
            : () {
                setState(() => rows.add(_Criterion(nextId++, '', '')));
                flush();
              },
        icon: Icon(Icons.add, size: 16),
        label: Text(
          kind == 'choice'
              ? context.strings.text("候補を追加")
              : context.strings.text("評価段階を追加"),
        ),
      ),
    ],
  );
}
