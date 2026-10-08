import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'lab_controller.dart';
import 'l10n/strings.dart';

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key, required this.lab});
  final LabController lab;
  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  ({int bytes, int files})? usage;
  String? usageError;

  @override
  void initState() {
    super.initState();
    refreshUsage();
  }

  Future<void> refreshUsage() async {
    try {
      final result = await widget.lab.mediaUsage();
      if (mounted) {
        setState(() {
          usage = result;
          usageError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => usageError = '使用容量を確認できませんでした');
    }
  }

  Future<void> clean({required bool all}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.strings.text(all ? '履歴と写真・録音を削除しますか？' : '使っていない素材を削除しますか？'),
        ),
        content: Text(
          context.strings.text(
            all
                ? 'すべての履歴と、取り込んだ写真・録音を削除します。現在の添付も外れます。モデルと自分のタスクは残ります。元の写真や取り込む前のファイルは変更しません。この操作は取り消せません。'
                : '履歴と現在の入力が使っている素材は残します。アプリに保存した、使っていない写真・録音だけを削除します。この操作は取り消せません。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.strings.text('キャンセル')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.strings.text('削除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || widget.lab.locked) return;
    if (all) {
      await widget.lab.deleteHistoryAndMedia();
    } else {
      await widget.lab.deleteUnusedMedia();
    }
    await refreshUsage();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.lab.error.isEmpty
                ? context.strings.text('保存データを削除しました')
                : context.strings.status(widget.lab.error),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.lab,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(context.strings.text('保存データ'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.photo_library_outlined, color: teal),
                      const SizedBox(height: 16),
                      Text(
                        context.strings.text('写真・録音'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        usage == null
                            ? '—'
                            : '${(usage!.bytes / 1000000).toStringAsFixed(1)} MB',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (usage != null)
                        Text(
                          context.strings.text('{p0}ファイル', {
                            'p0': '${usage!.files}',
                          }),
                        ),
                      if (usageError != null)
                        Text(context.strings.text(usageError!)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('delete-unused-media'),
                onPressed: widget.lab.locked ? null : () => clean(all: false),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(context.strings.text('使っていない素材を削除')),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('delete-history-media'),
                onPressed: widget.lab.locked ? null : () => clean(all: true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(context.strings.text('履歴と写真・録音をすべて削除')),
              ),
              const SizedBox(height: 20),
              Text(
                context.strings.text('モデルはモデル画面、自分のタスクはタスク一覧から削除できます。'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.strings.text('プライバシーポリシー'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: FutureBuilder<String>(
          future: rootBundle.loadString(
            context.strings.languageCode == 'ja'
                ? 'docs/privacy.md'
                : 'docs/privacy.en.md',
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(context.strings.text('説明を読み込めませんでした'));
            }
            if (!snapshot.hasData) return const CircularProgressIndicator();
            final paragraphs = snapshot.data!.trim().split(RegExp(r'\n\s*\n'));
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final paragraph in paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SelectableText(
                      paragraph.replaceFirst(RegExp(r'^#{1,3}\s+'), ''),
                      style: paragraph.startsWith('#')
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
