import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'domain.dart';
import 'lab_controller.dart';
import 'design.dart';
import 'l10n/strings.dart';
import 'results.dart';
import 'performance.dart';
import 'tasks.dart';
import 'task_widgets.dart';
import 'media_widgets.dart';
import 'data_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Liquid AI models',
    ], await rootBundle.loadString('assets/licenses/LFM-Open-License-1.0.txt'));
    yield LicenseEntryWithLineBreaks([
      'llama.cpp / ggml',
    ], await rootBundle.loadString('assets/licenses/llama.cpp-MIT.txt'));
    for (final entry in {
      'D1 Lab': 'Apache-2.0.txt',
      'nlohmann/json': 'json-MIT.txt',
      'stb_image': 'stb_image.txt',
      'miniaudio': 'miniaudio.txt',
      'SDWebImage': 'SDWebImage-MIT.txt',
      'SwiftyGif': 'SwiftyGif-MIT.txt',
      'DKImagePickerController': 'DKImagePickerController-MIT.txt',
      'DKPhotoGallery': 'DKPhotoGallery-MIT.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/licenses/${entry.value}'));
    }
  });
  runApp(D1Lab());
}

class D1Lab extends StatefulWidget {
  const D1Lab({
    super.key,
    this.controller,
    this.initialTab = 0,
    this.initialResults = false,
  });
  final LabController? controller;
  final int initialTab;
  final bool initialResults;
  @override
  State<D1Lab> createState() => _D1LabState();
}

class _D1LabState extends State<D1Lab> with WidgetsBindingObserver {
  late final LabController lab = widget.controller ?? LabController();
  late String localeCode;

  @override
  void initState() {
    super.initState();
    localeCode = lab.languageCode;
    lab.addListener(updateLocale);
    WidgetsBinding.instance.addObserver(this);
  }

  void updateLocale() {
    if (mounted && localeCode != lab.languageCode) {
      setState(() => localeCode = lab.languageCode);
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) => updateLocale();

  @override
  void dispose() {
    lab.removeListener(updateLocale);
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      lab.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'D1 Lab',
    debugShowCheckedModeBanner: false,
    locale: Locale(localeCode),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: labTheme(),
    home: LabScreen(
      controller: lab,
      initialTab: widget.initialTab,
      initialResults: widget.initialResults,
    ),
  );
}

class LabScreen extends StatefulWidget {
  const LabScreen({
    super.key,
    this.controller,
    this.initialTab = 0,
    this.initialResults = false,
  });
  final LabController? controller;
  final int initialTab;
  final bool initialResults;
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> with WidgetsBindingObserver {
  late final LabController lab;
  final stateField = TextEditingController();
  final taskNameField = TextEditingController();
  String? _nameTaskId, _taskNameError;
  String _saveInputKind = 'auto';
  late String _nameTaskTitle;
  bool _savingTask = false;
  late int tab;
  late bool showResults;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lab = widget.controller ?? LabController();
    tab = widget.initialTab;
    showResults = widget.initialResults;
    stateField.text = lab.state;
    _nameTaskId = lab.taskId;
    _nameTaskTitle = lab.taskTitle;
    taskNameField.text = lab.taskTitle;
    lab.addListener(_update);
    if (!lab.initialized) lab.init();
  }

  Future<void> execute({bool compare = false}) async {
    FocusScope.of(context).unfocus();
    await lab.execute(compare: compare);
    if (mounted && lab.error.isEmpty && lab.latest != null && !compare) {
      setState(() => showResults = true);
    }
  }

  void _update() {
    if (mounted) {
      if (stateField.text != lab.state) stateField.text = lab.state;
      if (_nameTaskId != lab.taskId || _nameTaskTitle != lab.taskTitle) {
        _nameTaskId = lab.taskId;
        _nameTaskTitle = lab.taskTitle;
        taskNameField.text = lab.taskTitle;
        _taskNameError = null;
        _saveInputKind = 'auto';
      }
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) lab.captureBackground(false);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      lab.captureBackground(true);
    }
  }

  @override
  void didHaveMemoryPressure() {
    lab.releaseRuntime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lab.removeListener(_update);
    if (widget.controller == null) {
      lab.dispose();
    }
    stateField.dispose();
    taskNameField.dispose();
    super.dispose();
  }

  void message(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.strings.status(text))));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              'd1',
              style: TextStyle(
                color: mint,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: -1,
              ),
            ),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'D1 Lab',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          key: const ValueKey('language-menu'),
          enabled: !lab.locked,
          tooltip: context.strings.text('表示言語'),
          icon: const Icon(Icons.translate_rounded, size: 20),
          initialValue: lab.language,
          onSelected: lab.setLanguage,
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: 'system',
              checked: lab.language == 'system',
              child: Text(context.strings.text('端末の言語')),
            ),
            CheckedPopupMenuItem(
              value: 'ja',
              checked: lab.language == 'ja',
              child: const Text('日本語'),
            ),
            CheckedPopupMenuItem(
              value: 'en',
              checked: lab.language == 'en',
              child: const Text('English'),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 145),
            child: LabBadge(
              lab.backend == 'metal' ? 'LOCAL · Metal' : 'LOCAL · CPU',
              icon: Icons.lock_outline,
            ),
          ),
        ),
      ],
    ),
    body: !lab.initialized
        ? Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: modelReadiness(),
                ),
                if (lab.busy)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: lab.progress),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(context.strings.progress(lab.phase)),
                            ),
                            TextButton(
                              onPressed: lab.deleting ? null : lab.cancel,
                              child: Text(context.strings.text("中止")),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (lab.error.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline),
                            SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                context.strings.status(lab.error),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                lab.error = '';
                                lab.changed();
                              },
                              icon: Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: switch (tab) {
                    0 => showResults ? resultPage() : playground(),
                    1 => comparison(),
                    2 => history(),
                    _ => models(),
                  },
                ),
                if (tab == 0 && !showResults)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            lab.locked ||
                                (!lab.needsDownload && lab.missingInput != null)
                            ? null
                            : lab.needsDownload
                            ? () => setState(() => tab = 3)
                            : execute,
                        icon: Icon(
                          lab.needsDownload
                              ? Icons.download_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Padding(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.strings.text(
                                  lab.needsDownload ? 'モデルを取得して始める' : '判定を実行する',
                                ),
                              ),
                              if (lab.missingInput != null)
                                Text(
                                  context.strings.status(lab.missingInput!),
                                  style: TextStyle(fontSize: 10, color: muted),
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    bottomNavigationBar: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: line)),
      ),
      child: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) {
          if (!lab.inputBusy) setState(() => tab = value);
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.tune_rounded, size: 21),
            label: context.strings.text("試す"),
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_rounded, size: 21),
            label: context.strings.text("比較"),
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded, size: 21),
            label: context.strings.text("履歴"),
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined, size: 21),
            label: context.strings.text("モデル"),
          ),
        ],
      ),
    ),
  );
  Widget page(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: constraints.maxWidth > 800 ? 800 : constraints.maxWidth,
        child: ListView(
          key: ValueKey('page-$tab-$showResults'),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: children,
        ),
      ),
    ),
  );
  Widget title(String text, [String? subtitle]) => Padding(
    padding: EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[SizedBox(height: 6), Text(subtitle)],
      ],
    ),
  );
  Widget box(List<Widget> children) => Card(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  Widget modelReadiness() {
    final ready = lab.modelReady;
    final status = lab.preparingModel
        ? context.strings.text('準備中…')
        : ready
        ? context.strings.text('準備完了')
        : lab.needsDownload
        ? context.strings.text('未取得')
        : context.strings.text('未準備');
    final preparation = durationMetric(lab.modelPreparationMs);
    final label = ready
        ? context.strings.text('解放')
        : lab.needsDownload
        ? context.strings.text('モデルを取得')
        : context.strings.text('モデルを準備');
    return Container(
      key: const ValueKey('model-readiness'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ready ? const Color(0xffeaf3e9) : Colors.white,
        border: Border.all(color: ready ? teal.withValues(alpha: .18) : line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${lab.selectedModel.name} · ${lab.backend == 'metal' ? 'Metal' : 'CPU'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: ready ? teal : muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        ready && lab.modelPreparationMs != null
                            ? '$status · ${preparation.value} ${preparation.unit}'
                            : status,
                        key: const ValueKey('model-readiness-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: ready ? teal : muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Tooltip(
              message: context.strings.text(
                ready
                    ? '待機を終了します。モデルファイルは残ります。'
                    : lab.needsDownload
                    ? 'モデル画面でダウンロードできます。'
                    : '先に読み込んで、すぐ判定できる状態にします。',
              ),
              child: FilledButton.tonalIcon(
                key: const ValueKey('prepare-model-button'),
                onPressed: lab.locked
                    ? null
                    : ready
                    ? lab.releaseRuntime
                    : lab.needsDownload
                    ? () => setState(() => tab = 3)
                    : lab.prepareModel,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 40),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: Icon(
                  ready
                      ? Icons.eject_rounded
                      : lab.needsDownload
                      ? Icons.download_rounded
                      : Icons.bolt_rounded,
                  size: 16,
                ),
                label: Text(label),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget playground() => page([
    modeSwitch(),
    TaskIntro(
      title: lab.taskTitle,
      modified: lab.taskModified,
      onChoose: lab.locked ? null : chooseTask,
      onHelp: showGuide,
    ),
    if (lab.inputKind != 'text') ...[
      SectionLabel(
        lab.inputKind == 'image'
            ? context.strings.text("01  判定する写真")
            : context.strings.text("01  判定する音声"),
      ),
      MediaInputCard(lab: lab, onImport: pickMedia),
    ],
    SectionLabel(
      lab.inputKind == 'text'
          ? context.strings.text("01  判断する文章")
          : context.strings.text("入力の補足"),
    ),
    box([
      DropdownButtonFormField<String>(
        value: lab.modelId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.strings.text("モデル")),
        items: modelSpecs
            .where(
              (m) =>
                  (lab.inputKind != 'audio' &&
                      !(lab.mediaPath != null && lab.mediaType == 'audio')) ||
                  m.id == 'omni',
            )
            .map(
              (m) => DropdownMenuItem(
                value: m.id,
                child: Text(
                  '${m.name} · ${m.quantization}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            )
            .toList(),
        onChanged: lab.locked
            ? null
            : (id) {
                lab.modelId = id!;
                lab.settingsChanged();
              },
      ),
      SizedBox(height: 16),
      TextField(
        controller: stateField,
        enabled: !lab.locked,
        minLines: lab.inputKind == 'text' ? 3 : 2,
        maxLines: 10,
        decoration: InputDecoration(
          labelText: lab.inputKind == 'text'
              ? context.strings.text("判断したい文章を入力")
              : context.strings.text("補足（任意）"),
          alignLabelWithHint: true,
        ),
        onChanged: (s) {
          lab.state = s;
          lab.draftChanged();
        },
      ),
    ]),
    SectionLabel(context.strings.text("02  モデルに聞くこと")),
    for (final q in lab.questions) questionEditor(q),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: lab.locked || lab.questions.length >= 8
            ? null
            : () {
                lab.questions.add(lab.newQuestion());
                lab.draftChanged();
              },
        icon: Icon(Icons.add),
        label: Text(context.strings.text("もう1つ判定を追加")),
      ),
    ),
    box([
      TextField(
        key: const ValueKey('task-name-field'),
        controller: taskNameField,
        enabled: !lab.locked && !_savingTask,
        maxLength: 50,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: context.strings.text('タスク名'),
          counterText: '',
          errorText: _taskNameError == null
              ? null
              : context.strings.text(_taskNameError!),
        ),
        onChanged: (_) {
          if (_taskNameError != null) setState(() => _taskNameError = null);
        },
      ),
      SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('task-kind-field'),
        value: _saveInputKind,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.strings.text('登録先')),
        items: [
          DropdownMenuItem(
            value: 'auto',
            child: Text(context.strings.text('自動選択')),
          ),
          for (final (kind, label) in [
            ('text', '文章'),
            ('image', '画像'),
            ('audio', '音声'),
          ])
            DropdownMenuItem(
              value: kind,
              child: Text(context.strings.text(label)),
            ),
        ],
        onChanged: lab.locked || _savingTask
            ? null
            : (kind) {
                if (kind != null) setState(() => _saveInputKind = kind);
              },
      ),
      SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('save-task-button'),
        onPressed: lab.locked || _savingTask ? null : saveCurrentTask,
        icon: Icon(Icons.bookmark_add_outlined, size: 17),
        label: Text(context.strings.text('この条件をタスクとして保存')),
      ),
    ]),
    SizedBox(height: 20),
    if (lab.inputKind == 'text')
      ExpansionTile(
        key: const ValueKey('optional-media'),
        tilePadding: EdgeInsets.zero,
        title: Text(context.strings.text('写真・音声を追加')),
        children: [MediaInputCard(lab: lab, onImport: pickMedia)],
      ),
  ]);
  Widget questionEditor(Question q) {
    final lines = q.criteria
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final summary = q.type == 'noul'
        ? context.strings.text("答え：はい / いいえ")
        : q.type == 'choice'
        ? context.strings.text("候補：{p0}", {
            'p0': lines.map((line) => line.split('|').first).join(' / '),
          })
        : context.strings.text("低い順の {p0} 段階で評価", {'p0': lines.length});
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(q.id),
          initiallyExpanded: q.instructions.isEmpty,
          tilePadding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Text(
            q.instructions.isEmpty
                ? context.strings.text("判定したいことを入力")
                : q.instructions,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              summary,
              style: TextStyle(fontSize: 11, color: teal, height: 1.5),
            ),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.strings.text("質問 {p0}", {
                      'p0': lab.questions.indexOf(q) + 1,
                    }),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: context.strings.text("質問を削除"),
                  onPressed: lab.locked || lab.questions.length <= 1
                      ? null
                      : () {
                          lab.questions.remove(q);
                          lab.draftChanged();
                        },
                  icon: Icon(Icons.delete_outline, size: 19),
                ),
              ],
            ),
            ChoiceControl(
              options: {
                'choice': context.strings.text("候補を選ぶ"),
                'noul': context.strings.text("はい・いいえ"),
                'score': context.strings.text("段階で評価"),
              },
              selected: q.type,
              onChanged: lab.locked
                  ? null
                  : (value) {
                      if (q.type == 'choice' && value == 'score') {
                        q.criteria = q.criteria
                            .split('\n')
                            .map((s) {
                              final at = s.indexOf('|');
                              return at >= 0 && s.substring(at + 1).isNotEmpty
                                  ? s.substring(at + 1)
                                  : s.split('|').first;
                            })
                            .join('\n');
                      }
                      q.type = value;
                      lab.draftChanged();
                    },
            ),
            SizedBox(height: 12),
            TextFormField(
              key: ValueKey('${q.id}-instructions'),
              initialValue: q.instructions,
              enabled: !lab.locked,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.strings.text("モデルに聞くこと"),
                hintText: context.strings.text("例：この口コミの印象を選んでください。"),
                alignLabelWithHint: true,
              ),
              onChanged: (s) {
                q.instructions = s;
                lab.draftChanged();
              },
            ),
            if (q.type != 'noul') ...[
              SizedBox(height: 18),
              CriteriaEditor(
                key: ValueKey('${q.id}-criteria'),
                question: q,
                enabled: !lab.locked,
                onChanged: lab.draftChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void showGuide() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .88,
        child: UsageGuide(taskHint: lab.taskCheck),
      ),
    ),
  );

  Future<void> chooseTask() async {
    var selectedKind = lab.inputKind;
    var sampleLanguage = lab.languageCode == 'ja' ? '日本語' : '英語';
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .88,
            child: AnimatedBuilder(
              animation: lab,
              builder: (context, _) => Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.strings.text("タスクを選ぶ"),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                    Text(
                      context.strings.text("用途を選ぶと、判定の指示・候補が入ります。"),
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final kind in ['text', 'image', 'audio'])
                          ChoiceChip(
                            label: Text(switch (kind) {
                              'image' => context.strings.text("画像"),
                              'audio' => context.strings.text("音声"),
                              _ => context.strings.text("文章"),
                            }),
                            selected: selectedKind == kind,
                            onSelected: (_) =>
                                setSheetState(() => selectedKind = kind),
                          ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (value, label) in [
                          ('日本語', '日本語'),
                          ('英語', 'English'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: sampleLanguage == value,
                            onSelected: (_) =>
                                setSheetState(() => sampleLanguage = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          SectionLabel(
                            context.strings.text('サンプルタスク'),
                            caption: context.strings.text('入力の言語は表示言語と別に選べます'),
                          ),
                          for (final task in allBuiltinTasks.where(
                            (t) =>
                                t.language == sampleLanguage &&
                                t.inputKind == selectedKind,
                          ))
                            taskTile(task, context),
                          SizedBox(height: 8),
                          SectionLabel(context.strings.text("自分のタスク")),
                          if (!lab.savedTasks.any(
                            (t) => t.inputKind == selectedKind,
                          ))
                            Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Text(
                                context.strings.text(
                                  "文章や候補を変えたら、「この条件をタスクとして保存」でここに追加できます。",
                                ),
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          for (final task in lab.savedTasks.where(
                            (t) => t.inputKind == selectedKind,
                          ))
                            taskTile(task, context, saved: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget taskTile(
    D1Task task,
    BuildContext sheetContext, {
    bool saved = false,
  }) => Card(
    child: ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: canvas,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          task.inputKind == 'image'
              ? Icons.photo_camera_outlined
              : task.inputKind == 'audio'
              ? Icons.mic_none_rounded
              : saved
              ? Icons.bookmark_outline
              : task.questions.first.type == 'choice'
              ? Icons.category_outlined
              : task.questions.first.type == 'noul'
              ? Icons.check_circle_outline
              : Icons.speed_outlined,
          color: teal,
          size: 18,
        ),
      ),
      title: Text(
        task.title,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        saved ? context.strings.text('自分で保存した入力の補足と判定条件') : task.description,
        style: TextStyle(fontSize: 11, color: muted),
      ),
      trailing: saved
          ? IconButton(
              tooltip: context.strings.text("保存したタスクを削除"),
              icon: Icon(Icons.delete_outline, size: 18),
              onPressed: lab.locked
                  ? null
                  : () async {
                      try {
                        await lab.deleteTask(task.id);
                      } catch (e) {
                        if (mounted) message(e.toString());
                      }
                    },
            )
          : Icon(Icons.chevron_right, size: 18),
      onTap: lab.locked
          ? null
          : () {
              lab.loadTask(task);
              setState(() => showResults = false);
              Navigator.pop(sheetContext);
            },
    ),
  );
  Future<void> saveCurrentTask() async {
    if (lab.locked || _savingTask) return;
    final name = taskNameField.text.trim();
    if (name.isEmpty) {
      setState(() => _taskNameError = 'タスク名を入力してください');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _savingTask = true);
    try {
      await lab.saveTask(name, kind: _saveInputKind);
      if (mounted) message(context.strings.text('タスクを保存しました。次はタスク一覧から選べます。'));
    } catch (e) {
      if (mounted) message(e.toString());
    } finally {
      if (mounted) setState(() => _savingTask = false);
    }
  }

  Widget comparison() => page([
    title(
      context.strings.text("同じ条件で、2モデルを比較"),
      context.strings.text("同じ入力で、答えと速度を見比べます。"),
    ),
    box([
      Text(
        context.strings.text("判断材料：{p0}", {'p0': lab.state}),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      SizedBox(height: 8),
      Text(
        context.strings.text("{p0}件の質問 · {p1}", {
          'p0': lab.questions.length,
          'p1': lab.backend == 'metal' ? 'Metal' : 'CPU',
        }),
      ),
      if (lab.inputKind == 'audio' ||
          (lab.mediaPath != null && lab.mediaType == 'audio')) ...[
        SizedBox(height: 12),
        Text(context.strings.text("音声入力はomni専用です。「試す」から実行してください。")),
      ] else if (lab.missingInput != null) ...[
        SizedBox(height: 12),
        Text(context.strings.status(lab.missingInput!)),
      ],
    ]),
    FilledButton.icon(
      onPressed:
          lab.locked ||
              lab.missingInput != null ||
              (lab.mediaPath != null && lab.mediaType == 'audio')
          ? null
          : () => execute(compare: true),
      icon: Icon(Icons.compare_arrows),
      label: Padding(
        padding: EdgeInsets.all(12),
        child: Text(context.strings.text("両モデルで比較する")),
      ),
    ),
    SizedBox(height: 16),
    if (lab.latest != null && lab.latest!['comparison'] == true) ...[
      ComparisonOverview(entry: lab.latest!),
      ...resultWidgets(lab.latest!),
    ],
  ]);
  Widget modeSwitch() => Container(
    margin: EdgeInsets.only(bottom: 18),
    padding: EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: line.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (final (result, label, icon) in [
          (false, context.strings.text("入力"), Icons.tune_rounded),
          (true, context.strings.text("結果"), Icons.bar_chart_rounded),
        ])
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: showResults == result
                    ? Colors.white
                    : Colors.transparent,
                foregroundColor: showResults == result ? ink : muted,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: lab.locked || (result && lab.latest == null)
                  ? null
                  : () => setState(() => showResults = result),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget resultPage() => page([
    modeSwitch(),
    title(context.strings.text("判断の結果")),
    if (lab.latest != null) ...[
      Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 18),
            childrenPadding: EdgeInsets.fromLTRB(18, 0, 18, 16),
            title: Text(
              lab.latest!['request']['state'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: ink),
            ),
            subtitle: Text(
              context.strings.text("{p0}件の質問{p1}", {
                'p0': (lab.latest!['request']['questions'] as List).length,
                'p1': lab.latest!['request']['mediaPath'] == null
                    ? ''
                    : lab.latest!['request']['mediaType'] == 'audio'
                    ? context.strings.text(" · 音声あり")
                    : context.strings.text(" · 画像あり"),
              }),
              style: TextStyle(fontSize: 10, color: muted),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  lab.latest!['request']['state'],
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      ...resultWidgets(lab.latest!),
    ],
    SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: lab.locked ? null : () => setState(() => showResults = false),
      icon: Icon(Icons.edit_outlined, size: 16),
      label: Text(context.strings.text("入力を編集する")),
    ),
  ]);
  List<Widget> resultWidgets(Map<String, dynamic> entry) => [
    if (entry['comparison'] == true && entry['wallTotalMs'] != null)
      Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LabBadge(
          context.strings.text("比較全体 {p0} {p1}", {
            'p0': durationMetric(metric(entry, 'wallTotalMs')).value,
            'p1': durationMetric(metric(entry, 'wallTotalMs')).unit,
          }),
          icon: Icons.timer_outlined,
        ),
      ),
    for (final run in entry['runs'])
      RunResults(
        run: Map<String, dynamic>.from(run),
        imageInfo:
            entry['request']['mediaType'] == 'image' &&
                entry['request']['mediaInfo'] is Map
            ? Map<String, dynamic>.from(entry['request']['mediaInfo'])
            : null,
        onJson: () => showJson(entry),
      ),
  ];
  Future<void> pickMedia(String type) async {
    if (lab.locked) return;
    lab.inputBusy = true;
    lab.changed();
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: type == 'image'
            ? ['png', 'jpg', 'jpeg', 'heic', 'heif']
            : ['wav', 'mp3', 'flac'],
      );
      final path = picked?.files.single.path;
      if (path != null && mounted) await lab.attach(path, type);
    } catch (e) {
      lab.error = 'ファイルを読み込めませんでした。$e';
    } finally {
      lab.inputBusy = false;
      lab.changed();
    }
  }

  Future<void> showJson(Map<String, dynamic> entry) async {
    final text = prettyJson(entry);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.strings.text("実行記録 JSON"),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (mounted) {
                          message('JSONをコピーしました');
                        }
                      },
                      child: Text(context.strings.text("コピー")),
                    ),
                    TextButton(
                      onPressed: () async {
                        final path = await FilePicker.platform.saveFile(
                          dialogTitle: context.strings.text("実行記録を保存"),
                          fileName: 'd1-${entry['id']}.json',
                          bytes: Uint8List.fromList(utf8.encode(text)),
                        );
                        if (path != null && Platform.isMacOS) {
                          await File(path).writeAsString(text);
                        }
                        if (path != null && mounted) {
                          message('JSONを保存しました');
                        }
                      },
                      child: Text(context.strings.text("保存")),
                    ),
                  ],
                ),
                Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget history() => page([
    title(
      context.strings.text("実行履歴"),
      context.strings.text("これまでの答えと速度を確認できます。"),
    ),
    if (lab.history.isEmpty)
      box([
        Icon(Icons.history, size: 32),
        SizedBox(height: 10),
        Text(context.strings.text("最初の判定を実行すると、ここに記録されます。")),
      ]),
    for (final entry in lab.history)
      Card(
        child: ListTile(
          title: Text(
            (entry['request']['state'] as String).replaceAll('\n', ' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${entry['at'].toString().substring(0, 19).replaceAll('T', ' ')} · ${entry['comparison'] == true ? context.strings.text("比較") : entry['runs'][0]['model']}',
          ),
          onTap: lab.locked
              ? null
              : () {
                  lab.restore(entry);
                  setState(() {
                    tab = 0;
                    showResults = true;
                  });
                },
          trailing: PopupMenuButton<String>(
            enabled: !lab.locked,
            onSelected: (value) async {
              if (value == 'json') {
                showJson(entry);
              } else {
                await confirmDeleteHistory(entry['id']);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'json',
                child: Text(context.strings.text("JSONを表示・保存")),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(context.strings.text("履歴を削除")),
              ),
            ],
          ),
        ),
      ),
  ]);
  Widget models() => page([
    title(
      context.strings.text("モデル"),
      context.strings.text("ダウンロード後はオフラインで使えます。"),
    ),
    box([
      Text(context.strings.text('Hugging Faceの公式配布元から取得します。')),
      if (lab.needsDownload) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: lab.locked ? null : lab.acquireRequired,
          icon: const Icon(Icons.download_rounded),
          label: Text(context.strings.text('このタスクに必要なモデルを取得')),
        ),
        const SizedBox(height: 8),
        Text(
          context.strings.text('必要なデータ：{p0} · 約{p1} GB', {
            'p0': lab.selectedModel.name,
            'p1':
                ((lab.selectedModel.base.bytes +
                            (lab.needsProjector
                                ? lab.selectedModel.projector.bytes
                                : 0)) /
                        1000000000)
                    .toStringAsFixed(2),
          }),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ]),
    for (final spec in modelSpecs)
      box([
        Text(spec.name, style: Theme.of(context).textTheme.titleLarge),
        Text(
          context.strings.text("{p0} · 本体 {p1} GB", {
            'p0': spec.quantization,
            'p1': (spec.base.bytes / 1000000000).toStringAsFixed(2),
          }),
        ),
        SizedBox(height: 8),
        assetRow(spec.base),
        SizedBox(height: 8),
        Text(
          context.strings.text(
            spec.id == '3b' ? '画像用の追加データ {p0} MB' : '画像・音声用の追加データ {p0} MB',
            {'p0': (spec.projector.bytes / 1000000).toStringAsFixed(0)},
          ),
        ),
        assetRow(spec.projector),
        const Divider(height: 24),
        Text(
          context.strings.text('使用容量：{p0} MB', {
            'p0': (lab.modelStoredBytes(spec) / 1000000).toStringAsFixed(1),
          }),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton.icon(
          key: ValueKey('delete-model-${spec.id}'),
          onPressed: lab.locked || lab.modelStoredBytes(spec) == 0
              ? null
              : () => confirmDeleteModel(spec),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(context.strings.text('モデルファイルを削除')),
        ),
      ]),
    Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('advanced-settings'),
          title: Text(context.strings.text('詳細設定')),
          childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            ChoiceControl(
              options: {'metal': 'Metal GPU', 'cpu': 'CPU'},
              selected: lab.backend,
              onChanged: lab.locked
                  ? null
                  : (value) {
                      lab.backend = value;
                      lab.settingsChanged();
                    },
            ),
            SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: lab.contextTokens,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.strings.text("アプリの入力上限"),
              ),
              items: [512, 1024, 2048, 4096]
                  .map(
                    (n) => DropdownMenuItem(value: n, child: Text('$n tokens')),
                  )
                  .toList(),
              onChanged: lab.locked
                  ? null
                  : (n) {
                      lab.contextTokens = n!;
                      lab.settingsChanged();
                    },
            ),
            SwitchListTile(
              key: const ValueKey('keep-model-loaded'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.strings.text('モデルを読み込んだまま待機')),
              subtitle: Text(
                context.strings.text('繰り返しの判定が速くなります。アプリを離れると待機を終了します。'),
              ),
              value: lab.keepModelLoaded,
              onChanged: lab.locked
                  ? null
                  : (value) {
                      lab.keepModelLoaded = value;
                      lab.settingsChanged();
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.strings.text("omniのテキスト確率を校正")),
              subtitle: Text(context.strings.text("モデルの推奨設定を使います。")),
              value: lab.calibrated,
              onChanged: lab.locked
                  ? null
                  : (value) {
                      lab.calibrated = value;
                      lab.settingsChanged();
                    },
            ),
          ],
        ),
      ),
    ),
    TextButton.icon(
      key: const ValueKey('data-management'),
      onPressed: lab.locked
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DataManagementPage(lab: lab),
              ),
            ),
      icon: const Icon(Icons.storage_rounded),
      label: Text(context.strings.text('保存データ')),
    ),
    TextButton.icon(
      key: const ValueKey('privacy-policy'),
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage())),
      icon: const Icon(Icons.privacy_tip_outlined),
      label: Text(context.strings.text('プライバシーポリシー')),
    ),
    TextButton.icon(
      onPressed: () => showLicensePage(
        context: context,
        applicationName: 'D1 Lab',
        applicationVersion: '0.13.0',
      ),
      icon: Icon(Icons.description_outlined),
      label: Text(context.strings.text("モデル・ソフトウェアのライセンス")),
    ),
  ]);
  Future<void> confirmDeleteHistory(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('履歴を削除しますか？')),
        content: Text(
          context.strings.text(
            'この履歴と、ほかの履歴や現在の入力が使っていない素材を削除します。この操作は取り消せません。',
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
    if (confirmed == true && mounted && !lab.locked) {
      await lab.deleteHistory(id);
    }
  }

  Future<void> confirmDeleteModel(ModelSpec spec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('{p0}を削除しますか？', {'p0': spec.name})),
        content: Text(
          context.strings.text('モデル関連のファイル（{p0} MB）を削除します。タスクと履歴は残ります。', {
            'p0': (lab.modelStoredBytes(spec) / 1000000).toStringAsFixed(1),
          }),
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
    if (confirmed == true && mounted) {
      await lab.deleteModel(spec);
      if (mounted && lab.error.isEmpty) message('モデルファイルを削除しました');
    }
  }

  Widget assetRow(ModelAsset asset) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        lab.available[asset.filename] == true
            ? context.strings.text("✓ 取得済み")
            : context.strings.text("未取得"),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: lab.locked ? null : () => lab.acquire(asset),
            icon: Icon(Icons.download),
            label: Text(
              lab.available[asset.filename] == true
                  ? context.strings.text("再取得")
                  : context.strings.text("取得・再開"),
            ),
          ),
          TextButton.icon(
            onPressed: lab.locked
                ? null
                : () async {
                    final picked = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['gguf'],
                    );
                    final path = picked?.files.single.path;
                    if (path != null) {
                      await lab.acquire(asset, importPath: path);
                    }
                  },
            icon: Icon(Icons.folder_open),
            label: Text(context.strings.text("ファイルを取り込む")),
          ),
        ],
      ),
    ],
  );
}
