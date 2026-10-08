import 'dart:io';
import 'package:flutter/material.dart';
import 'design.dart';
import 'l10n/strings.dart';
import 'lab_controller.dart';

class MediaInputCard extends StatelessWidget {
  const MediaInputCard({super.key, required this.lab, required this.onImport});
  final LabController lab;
  final void Function(String type) onImport;
  @override
  Widget build(BuildContext context) {
    final image = lab.inputKind != 'audio';
    final audio = lab.inputKind != 'image';
    final duration = lab.mediaInfo?['durationSeconds'] as num?;
    final width = lab.mediaInfo?['width'];
    final height = lab.mediaInfo?['height'];
    final audioCaption = duration != null
        ? context.strings.text("{p0}秒 · マイク録音", {
            'p0': duration.toStringAsFixed(1),
          })
        : context.strings.text("音声ファイル · 最大30秒");
    return Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lab.recording) ...[
              Row(
                children: [
                  Icon(Icons.mic_rounded, color: teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.strings.text("録音中"),
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${(lab.recordingElapsed.inMilliseconds / 1000).toStringAsFixed(1)} / 30 s',
                    style: TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Semantics(
                label: context.strings.text("マイクの入力音量"),
                child: Row(
                  children: List.generate(
                    24,
                    (i) => Expanded(
                      child: Container(
                        height: 24 + (i % 5) * 5,
                        margin: EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i / 24 < lab.recordingLevel ? teal : line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => lab.stopRecording(),
                  icon: Icon(Icons.stop_rounded),
                  label: Text(context.strings.text("停止して使う")),
                ),
              ),
              TextButton(
                onPressed: () => lab.stopRecording(discard: true),
                child: Text(context.strings.text("録音を破棄")),
              ),
            ] else ...[
              if (lab.mediaPath != null) ...[
                if (lab.mediaType == 'image')
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(lab.mediaPath!),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Text(context.strings.text("写真のプレビューを読み込めません")),
                    ),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    lab.mediaType == 'image'
                        ? Icons.check_circle_outline
                        : Icons.graphic_eq,
                    color: teal,
                  ),
                  title: Text(
                    lab.mediaType == 'image'
                        ? context.strings.text("写真をセットしました")
                        : context.strings.text("音声をセットしました"),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    lab.mediaType == 'audio'
                        ? audioCaption
                        : width != null && height != null
                        ? context.strings.text('判定する画像：{p0} × {p1} px', {
                            'p0': width,
                            'p1': height,
                          })
                        : context.strings.text("この写真で判定します"),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  trailing: IconButton(
                    onPressed: lab.locked ? null : lab.removeMedia,
                    tooltip: context.strings.text("添付を解除"),
                    icon: Icon(Icons.close, size: 18),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        image
                            ? Icons.add_photo_alternate_outlined
                            : Icons.mic_none_rounded,
                        size: 32,
                        color: teal,
                      ),
                      SizedBox(height: 8),
                      Text(
                        image
                            ? context.strings.text("見せたいものを、写真で")
                            : context.strings.text("声を録音して、操作を判定"),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
              ],
              if (image) ...[
                InputDecorator(
                  key: ValueKey('image-size-${lab.imageMaxPixels}'),
                  decoration: InputDecoration(
                    labelText: context.strings.text('画像の長辺'),
                    helperText: context.strings.text('小さくすると処理が軽くなります。'),
                    helperMaxLines: 2,
                    enabled: !lab.locked,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: lab.imageMaxPixels,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final size in imageSizeOptions)
                          DropdownMenuItem(
                            value: size,
                            child: Text('$size px'),
                          ),
                      ],
                      onChanged: lab.locked
                          ? null
                          : (value) {
                              if (value != null) lab.setImageMaxPixels(value);
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (image && (Platform.isIOS || Platform.isAndroid))
                    OutlinedButton.icon(
                      onPressed: lab.locked
                          ? null
                          : () => lab.choosePhoto(camera: true),
                      icon: Icon(Icons.camera_alt_outlined, size: 18),
                      label: Text(context.strings.text("カメラで撮る")),
                    ),
                  if (image)
                    OutlinedButton.icon(
                      onPressed: lab.locked
                          ? null
                          : () => lab.choosePhoto(camera: false),
                      icon: Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(context.strings.text("写真から選ぶ")),
                    ),
                  if (audio)
                    OutlinedButton.icon(
                      onPressed: lab.locked ? null : lab.startRecording,
                      icon: Icon(Icons.mic_none_rounded, size: 18),
                      label: Text(context.strings.text("マイクで録音")),
                    ),
                ],
              ),
              if (lab.inputBusy) ...[
                SizedBox(height: 12),
                LinearProgressIndicator(),
                SizedBox(height: 6),
                Text(
                  context.strings.text("入力を準備しています…"),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
              if (audio) ...[
                SizedBox(height: 8),
                Text(
                  context.strings.text('録音は最大30秒 · omniで判定'),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  context.strings.text("ファイルから取り込む"),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      if (image)
                        TextButton.icon(
                          onPressed: lab.locked
                              ? null
                              : () => onImport('image'),
                          icon: Icon(Icons.image_outlined, size: 16),
                          label: Text(context.strings.text("画像ファイル")),
                        ),
                      if (audio)
                        TextButton.icon(
                          onPressed: lab.locked
                              ? null
                              : () => onImport('audio'),
                          icon: Icon(Icons.audio_file_outlined, size: 16),
                          label: Text(context.strings.text("音声ファイル")),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
