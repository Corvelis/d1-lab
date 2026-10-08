"""Add d1-omni media masks and LFM2-compatible vision/audio adapters."""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'third_party/llama.cpp'

def edit(path, replacements):
    p = root / path
    s = p.read_text()
    for old, new in replacements:
        if new in s: continue
        assert old in s, (path, old[:100])
        s = s.replace(old, new, 1)
    if s != p.read_text(): p.write_text(s)

edit('src/models/lfm2.cpp', [
('class d1_type_input final', '''// D1_LAB_MEDIA: prefix rows cannot see text; the head reads only text keys.
class d1_mask_input final : public llm_graph_input_attn_no_cache {
public:
    bool head;
    ggml_tensor * keep_right = nullptr;
    d1_mask_input(const llama_hparams & hp, const llama_cparams & cp, bool is_head) :
        llm_graph_input_attn_no_cache(hp, cp), head(is_head) {}
    void set_input(const llama_ubatch * b) override {
        int prefix = 0;
        if (b->type) while(prefix < int(b->n_tokens) && b->type[prefix] == 1) ++prefix;
        std::vector<float> mask(b->n_tokens * b->n_tokens, 0);
        for(uint32_t q=0;q<b->n_tokens;++q) for(uint32_t k=0;k<b->n_tokens;++k) {
            if(head ? k < uint32_t(prefix) : (q < uint32_t(prefix) && k >= uint32_t(prefix)))
                mask[q*b->n_tokens+k] = -INFINITY;
        }
        ggml_backend_tensor_set(self_kq_mask, mask.data(), 0, mask.size()*sizeof(float));
        if(keep_right) {
            std::vector<float> keep(b->n_tokens,1.0f);
            if(prefix>0) keep[prefix-1]=0;
            ggml_backend_tensor_set(keep_right,keep.data(),0,keep.size()*sizeof(float));
        }
    }
};
class d1_type_input final'''),
('    // lambda helpers for readability', '''    auto make_d1_mask = [this](bool head) {
        auto inp = std::make_unique<d1_mask_input>(hparams,cparams,head);
        inp->self_kq_mask = ggml_new_tensor_4d(ctx0,GGML_TYPE_F32,n_tokens,n_tokens,1,1);
        ggml_set_input(inp->self_kq_mask);
        inp->self_kq_mask_cnv=inp->self_kq_mask;
        if(!head) {
            inp->keep_right = ggml_new_tensor_3d(ctx0,GGML_TYPE_F32,n_tokens,1,1);
            ggml_set_input(inp->keep_right);
        }
        return static_cast<d1_mask_input *>(res->add_input(std::move(inp)));
    };
    const auto & d1_model = static_cast<const llama_model_lfm2 &>(model);
    auto * d1_trunk_mask = d1_model.d1_omni ? make_d1_mask(false) : nullptr;
    // lambda helpers for readability'''),
('auto build_attn_block = [&model, this]', 'auto build_attn_block = [&model, this, d1_trunk_mask]'),
('        cur = build_attn(inp_attn,\n', '''        if(d1_trunk_mask) {
            return build_attn(d1_trunk_mask,model.layers[il].wo,nullptr,nullptr,q,k,v,
                              nullptr,nullptr,nullptr,1.0f/sqrtf(float(n_embd_head)),il);
        }
        cur = build_attn(inp_attn,
'''),
('auto build_shortconv_block = [&model, this]', 'auto build_shortconv_block = [&model, this, d1_trunk_mask]'),
('        // read conv state', '''        if(d1_trunk_mask) {
            auto * padded = ggml_pad_ext(ctx0,bx,1,1,0,0,0,0,0,0);
            auto * kernel = model.layers[il].shortconv.conv;
            ggml_tensor * y = nullptr;
            for(int tap=0;tap<3;++tap) {
                auto * slice=ggml_view_3d(ctx0,padded,n_seq_tokens,n_embd,1,padded->nb[1],padded->nb[2],tap*padded->nb[0]);
                if(tap==2) slice=ggml_mul(ctx0,slice,d1_trunk_mask->keep_right);
                auto * weight=ggml_view_3d(ctx0,kernel,1,n_embd,1,kernel->nb[1],kernel->nb[1]*n_embd,tap*kernel->nb[0]);
                auto * term=ggml_mul(ctx0,slice,weight);
                y=y?ggml_add(ctx0,y,term):term;
            }
            y=ggml_mul(ctx0,c,ggml_cont(ctx0,ggml_transpose(ctx0,y)));
            y=build_lora_mm(model.layers[il].shortconv.out_proj,y);
            return ggml_reshape_2d(ctx0,y,n_embd,n_seq_tokens);
        }
        // read conv state'''),
('    const auto & d1_model = static_cast<const llama_model_lfm2 &>(model);\n    const int trunk_layers', '    // D1_LAB_TRUNK_LAYERS\n    const int trunk_layers'),
('auto * head_attn = build_attn_inp_no_cache();', 'auto * head_attn = make_d1_mask(true);'),
('    if constexpr (iswa) {\n        inp_hybrid = build_inp_mem_hybrid_iswa();\n    } else {\n        inp_hybrid = build_inp_mem_hybrid();\n    }', '''    if (!d1_model.d1_omni) {
        if constexpr (iswa) {
            inp_hybrid = build_inp_mem_hybrid_iswa();
        } else {
            inp_hybrid = build_inp_mem_hybrid();
        }
    }'''),
('build_shortconv_block(cur, inp_hybrid->get_recr(), il)', 'build_shortconv_block(cur, inp_hybrid ? inp_hybrid->get_recr() : nullptr, il)'),
('build_attn_block(cur, inp_pos, inp_hybrid->get_attn(), il)', 'build_attn_block(cur, inp_pos, inp_hybrid ? inp_hybrid->get_attn() : nullptr, il)'),
])
edit('tools/mtmd/clip-impl.h', [('    for (const auto & pair : PROJECTOR_TYPE_NAMES) {', '''    if(str == "d1omni_v") return PROJECTOR_TYPE_LFM2;
    if(str == "d1omni_a") return PROJECTOR_TYPE_LFM2A;
    for (const auto & pair : PROJECTOR_TYPE_NAMES) {''')])
edit('tools/mtmd/clip-model.h', [('    clip_hparams hparams;\n', '''    clip_hparams hparams;
    bool d1_omni = false;
    ggml_tensor * d1_res_norm_w=nullptr, *d1_res_norm_b=nullptr;
    ggml_tensor * d1_res_down_w=nullptr, *d1_res_down_b=nullptr;
    ggml_tensor * d1_res_up_w=nullptr, *d1_res_up_b=nullptr;
''')])
edit('tools/mtmd/clip.cpp', [
('            model.proj_type = clip_projector_type_from_string(proj_type);', '''            model.proj_type = clip_projector_type_from_string(proj_type);
            model.d1_omni = proj_type == "d1omni_v" || proj_type == "d1omni_a";'''),
('            return ctx->model.position_embeddings->ne[0];', '            return ctx->model.d1_omni ? ctx->model.hparams.projection_dim : ctx->model.position_embeddings->ne[0];'),
('                    model.mm_3_b = get_tensor(string_format(TN_MM_AUDIO_MLP, 3, "bias"));\n\n                    for (int il = 0; il < hparams.n_layer; ++il) {', '''                    model.mm_3_b = get_tensor(string_format(TN_MM_AUDIO_MLP, 3, "bias"));
                    // D1_LAB_AUDIO_RESIDUAL
                    if(model.d1_omni) {
                        model.d1_res_norm_w=get_tensor("mm.a.mlp.4.weight");
                        model.d1_res_norm_b=get_tensor("mm.a.mlp.4.bias");
                        model.d1_res_down_w=get_tensor("mm.a.mlp.5.weight");
                        model.d1_res_down_b=get_tensor("mm.a.mlp.5.bias");
                        model.d1_res_up_w=get_tensor("mm.a.mlp.6.weight");
                        model.d1_res_up_b=get_tensor("mm.a.mlp.6.bias");
                    }

                    for (int il = 0; il < hparams.n_layer; ++il) {'''),
])
edit('tools/mtmd/models/conformer.cpp', [
('    GGML_ASSERT(model.position_embeddings->ne[1] >= n_pos);', '    if(!model.d1_omni) GGML_ASSERT(model.position_embeddings->ne[1] >= n_pos);'),
('    cb(cur, "projected", -1);', '''    if(model.d1_omni) {
        auto * norm=build_norm(cur,model.d1_res_norm_w,model.d1_res_norm_b,NORM_TYPE_NORMAL,1e-5,-1);
        auto * residual=build_ffn(norm,model.d1_res_down_w,model.d1_res_down_b,nullptr,nullptr,
                                 model.d1_res_up_w,model.d1_res_up_b,FFN_GELU_ERF,-1);
        cur=ggml_add(ctx0,cur,residual);
    }
    cb(cur, "projected", -1);'''),
])
edit('tools/mtmd/models/siglip.cpp', [
('            FFN_GELU,\n            -1);', '            model.d1_omni ? FFN_GELU_ERF : FFN_GELU,\n            -1);')
])
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
