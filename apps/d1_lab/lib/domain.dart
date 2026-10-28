import 'dart:convert';

class Question {
  Question({
    required this.id,
    this.type = 'choice',
    this.instructions = '',
    this.criteria = '',
  });
  final String id;
  String type;
  String instructions;
  String criteria;
  Map<String, dynamic> toJson() {
    if (instructions.trim().isEmpty) {
      throw const FormatException('判定指示を入力してください');
    }
    final result = <String, dynamic>{
      'type': type,
      'instructions': instructions.trim(),
    };
    if (type == 'choice') {
      final options = criteria
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
            final separator = line.indexOf('|');
            return <String, String>{
              'name': (separator < 0 ? line : line.substring(0, separator))
                  .trim(),
              'description': separator < 0
                  ? ''
                  : line.substring(separator + 1).trim(),
            };
          })
          .toList();
      final names = options.map((o) => o['name']).toSet();
      if (options.length < 2 ||
          options.length > 26 ||
          names.length != options.length ||
          names.contains('')) {
        throw const FormatException('選択肢は重複しない名前で2〜26個にしてください');
      }
      result['options'] = options;
    } else if (type == 'score') {
      final levels = criteria
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (levels.length < 2 || levels.length > 10) {
        throw const FormatException('評価段階を低い順に2〜10個入力してください');
      }
      result['levels'] = levels;
    } else if (type != 'noul') {
      throw const FormatException('質問の種類が不正です');
    }
    return result;
  }

  Map<String, dynamic> get draft => {
    'id': id,
    'type': type,
    'instructions': instructions,
    'criteria': criteria,
  };
  factory Question.fromDraft(Map<String, dynamic> j) => Question(
    id: j['id'],
    type: j['type'],
    instructions: j['instructions'],
    criteria: j['criteria'],
  );
}

class ModelAsset {
  const ModelAsset(
    this.repository,
    this.revision,
    this.filename,
    this.bytes,
    this.sha256, {
    this.previousVersions = const [],
  });
  final String repository, revision, filename, sha256;
  final int bytes;
  // Previously verified releases remain usable without another download.
  final List<ModelAsset> previousVersions;
  Iterable<ModelAsset> get supportedVersions sync* {
    yield this;
    yield* previousVersions;
  }

  Uri get uri => Uri.parse(
    'https://huggingface.co/$repository/resolve/$revision/$filename',
  );
}

class ModelSpec {
  const ModelSpec(
    this.id,
    this.name,
    this.quantization,
    this.base,
    this.projector, {
    this.generation = 'lfm2',
    this.supportsAudio = false,
  });
  final String id, name, quantization;
  final String generation;
  final bool supportsAudio;
  final ModelAsset base, projector;
  bool get isLfm3 => generation == 'lfm3';
  bool get isBidirectional => isLfm3 || supportsAudio;
  bool get supportsCalibration => isLfm3 || supportsAudio;
}

const modelSpecs = [
  ModelSpec(
    '2b',
    'd1-2B',
    'Q4_K_M',
    ModelAsset(
      'LiquidAI/d1-2B-GGUF',
      '63be75e6586882defeb706ed4bda812d90256a6d',
      'd1-2B-Q4_K_M.gguf',
      1099629888,
      'adca5789ad30ae6027e8e936749bb9f19673097492ab26fa1c5b69643ca50b4b',
    ),
    ModelAsset(
      'LiquidAI/d1-2B-GGUF',
      '63be75e6586882defeb706ed4bda812d90256a6d',
      'mmproj-d1-2B-Q8_0.gguf',
      203031584,
      '62cc6d74fd1e5b1d6b48518566bf4c0cfd2468079a0c096ea323b74eed01e0d1',
    ),
    generation: 'lfm3',
  ),
  ModelSpec(
    'omni2b',
    'd1-Omni-2B',
    'Q8_0',
    ModelAsset(
      'LiquidAI/d1-Omni-2B-GGUF',
      '807fea1af72ebaef653404f64a4bec8e5afeedea',
      'd1-Omni-2B-Q8_0.gguf',
      1846241184,
      'aedf1a7c341b4281979423dbc39e9c3d3ad1da8834156c8e75af5399ca3b0861',
    ),
    ModelAsset(
      'LiquidAI/d1-Omni-2B-GGUF',
      '807fea1af72ebaef653404f64a4bec8e5afeedea',
      'mmproj-d1-Omni-2B-Q8_0.gguf',
      326104096,
      '31778160ac0ec70f9b59f296aa1c8e70cbd1eb7e3a3ff873d695aaa4c7b8d674',
    ),
    generation: 'lfm3',
    supportsAudio: true,
  ),
  ModelSpec(
    '3b',
    'd1-3B',
    'Q4_K_M',
    ModelAsset(
      'LiquidAI/d1-3B-GGUF',
      'bb1e436ea78eb96a3f1acb6da865f70c2fbeb563',
      'd1-3B-Q4_K_M.gguf',
      1674456672,
      '16aff27ea2eefdc32b9897f43854a5d3170c1dc8dccb9c756905af30a4e22402',
      previousVersions: [
        ModelAsset(
          'LiquidAI/d1-3B-GGUF',
          '9bf7242ada80890821d6459b1a4ff615a0f72bd5',
          'd1-3B-Q4_K_M.gguf',
          1674456352,
          '8cff1d4500d07e1b19bff706b078830cf4fa69f32d6acf44e61b0dd2041b3d8a',
        ),
      ],
    ),
    ModelAsset(
      'LiquidAI/d1-3B-GGUF',
      'bb1e436ea78eb96a3f1acb6da865f70c2fbeb563',
      'mmproj-d1-3B-Q8_0.gguf',
      583109728,
      '2505920ce464b7c54acd8b7b74a931c0c671f06d0c8833760b2fbceeb253e92a',
    ),
  ),
  ModelSpec(
    'omni',
    'd1-omni-600M',
    'Q8_0',
    ModelAsset(
      'LiquidAI/d1-omni-600M-GGUF',
      '04397145ed8381350403aa556db0ec6a49dd8c07',
      'd1-omni-600M-Q8_0.gguf',
      407207584,
      'cd94463f4cac9c700ec6750df8df005bb6846de410e159d1f5e985e1171693d3',
      previousVersions: [
        ModelAsset(
          'LiquidAI/d1-omni-600M-GGUF',
          'aa1447a4750aa0cdc13bce9f90468c395e940b60',
          'd1-omni-600M-Q8_0.gguf',
          407207552,
          '05d9c9a08c0a12c993a4ab05c1990a7c31c93ee58134b852d73d2d83ee1e6417',
        ),
      ],
    ),
    ModelAsset(
      'LiquidAI/d1-omni-600M-GGUF',
      '04397145ed8381350403aa556db0ec6a49dd8c07',
      'mmproj-d1-omni-600M-Q8_0.gguf',
      262791232,
      'df887978550cdbb45f0f57d7b436a0f844689f9f561395a144ced500606c3a89',
      previousVersions: [
        ModelAsset(
          'LiquidAI/d1-omni-600M-GGUF',
          'aa1447a4750aa0cdc13bce9f90468c395e940b60',
          'mmproj-d1-omni-600M-Q8_0.gguf',
          262791200,
          'd6637f3599e76a5b5a87d75e947d3253b621b2fd231fc92303ad63ab0e44389e',
        ),
      ],
    ),
    supportsAudio: true,
  ),
];

Map<String, dynamic> snapshot(
  String state,
  List<Question> questions,
  bool calibrated, {
  bool allowEmptyState = false,
}) {
  if (!allowEmptyState && state.trim().isEmpty) {
    throw const FormatException('判断材料を入力してください');
  }
  if (questions.isEmpty) throw const FormatException('質問を追加してください');
  // A JSON round trip freezes the draft before async loading or a two-model comparison.
  return jsonDecode(
        jsonEncode({
          'state': state,
          'questions': questions.map((q) => q.toJson()).toList(),
          'calibrated': calibrated,
        }),
      )
      as Map<String, dynamic>;
}

String prettyJson(Object object) =>
    const JsonEncoder.withIndent('  ').convert(object);
