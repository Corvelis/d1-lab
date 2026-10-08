# decision_bridge

[English](README.en.md)

D1 LabのFlutter推論プラグインです。iOS 16以上とApple SiliconのmacOS 14以上に対応し、CPUとMetalでd1-3B / d1-omni-600Mを実行します。

アプリを試す手順は [D1 Lab](../../apps/d1_lab/README.md)、環境の準備は [ビルド手順](../../apps/d1_lab/docs/building.md) を参照してください。

## ランタイムを準備する

リポジトリのルートから実行します。

```sh
python3 native/decision_bridge/scripts/prepare_runtime.py --source
```

固定版のllama.cppをSHA-256で確認し、d1用パッチを適用してXCFrameworkを生成します。iOS実機、Apple SiliconのiOSシミュレータ、macOSのarm64を含みます。Metalのカーネルソースを埋め込みます。

ビルド済みランタイムも、同じスクリプトで検証して配置できます。取得方法は [ビルド手順](../../apps/d1_lab/docs/building.md) に記載しています。一般のllama.cppバイナリにはこのパッケージのd1用パッチが含まれないため、このパッケージに対応するランタイムを使用してください。

## ソースとライセンス

上流の版とアーカイブのSHA-256は `runtime.lock.json` に固定しています。`patch_runtime.py` と `patch_media.py` がd1の判定ヘッドとメディア処理を追加します。C APIは `include/decision.h` にあります。

このパッケージのソースは [Apache-2.0](LICENSE) です。同梱する依存コードのライセンスは [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md) と `licenses/` にあります。モデルのライセンスは別です。
