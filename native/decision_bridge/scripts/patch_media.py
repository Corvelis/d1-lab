"""Add the bounded audio-file reader used by the legacy omni adapter."""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'third_party/llama.cpp'

def edit(path, replacements):
    p = root / path
    s = p.read_text()
    for old, new in replacements:
        if new in s: continue
        assert old in s, (path, old[:100])
        s = s.replace(old, new, 1)
    p.write_text(s)

edit('tools/mtmd/mtmd-helper.cpp', [('#define STB_IMAGE_IMPLEMENTATION', '''// Decode audio using the miniaudio instance in this translation unit.
std::vector<float> d1_read_audio_file(const std::string & path) {
    ma_decoder decoder;
    auto config=ma_decoder_config_init(ma_format_f32,1,16000);
    if(ma_decoder_init_file(path.c_str(),&config,&decoder)!=MA_SUCCESS)
        throw std::runtime_error("音声ファイルを読み込めませんでした");
    std::vector<float> samples(480001); ma_uint64 read=0;
    ma_decoder_read_pcm_frames(&decoder,samples.data(),samples.size(),&read);
    ma_decoder_uninit(&decoder); samples.resize(read); return samples;
}
#define STB_IMAGE_IMPLEMENTATION''')])
