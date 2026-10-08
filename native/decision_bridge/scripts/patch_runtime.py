"""Add the d1-omni decision head to the pinned llama.cpp source."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'third_party/llama.cpp'
p = root / 'src/models/lfm2.cpp'
s = p.read_text()
if '// D1_LAB_HEAD' in s:
    old_type = '    d1_omni = decision_type == "d1omni";'
    new_type = '    d1_omni = decision_type == "d1omni" || decision_type == "lfm2-d1-omni";'
    if old_type in s:
        p.write_text(s.replace(old_type, new_type, 1))
        print('d1 model identifiers updated')
    else:
        assert new_type in s, 'Unexpected d1 model type detection'
    print('d1 patch already applied')
    raise SystemExit(0)

def replace(old, new):
    global s
    assert old in s, old[:100]
    s = s.replace(old, new, 1)

replace('#include <algorithm>', '''#include <algorithm>
#include "../llama-batch.h"
#include "ggml-backend.h"

// D1_LAB_HEAD: one question per sequence, type is supplied through decision_order.
class d1_type_input final : public llm_graph_input_i {
public:
    ggml_tensor * ids;
    explicit d1_type_input(ggml_tensor * t) : ids(t) {}
    void set_input(const llama_ubatch * b) override {
        int32_t type = 0;
        if (b->decision_order) for (uint32_t i = 0; i < b->n_tokens; ++i) {
            if (b->decision_order[i] == 1) type = 2;
            if (b->decision_order[i] == 3) type = 1;
        }
        ggml_backend_tensor_set(ids, &type, 0, sizeof(type));
    }
};''')
replace('    hparams.n_layer_dense_lead = hparams.n_layer();', '''    hparams.n_layer_dense_lead = hparams.n_layer();
    std::string decision_type;
    ml.get_key("lfm2.decision.type", decision_type, false);
    d1_omni = decision_type == "d1omni" || decision_type == "lfm2-d1-omni";
    if (d1_omni) {
        ml.get_key(LLM_KV_DECISION_BLOCK_COUNT, d1_head_layers);
        hparams.n_embd_out_impl = 1;
        hparams.f_norm_eps = 1e-5f;
    }''')
replace('    for (int i = 0; i < n_layer; ++i) {', '''    if (d1_omni) {
        type_embd = create_tensor(tn(LLM_TENSOR_TOKEN_TYPES, "weight"), {n_embd, 3}, 0);
        cls_norm = create_tensor(tn(LLM_TENSOR_CLS_NORM, "weight"), {n_embd}, 0);
        cls_norm_b = create_tensor(tn(LLM_TENSOR_CLS_NORM, "bias"), {n_embd}, 0);
        cls = create_tensor(tn(LLM_TENSOR_CLS, "weight"), {n_embd, n_embd}, 0);
        cls_b = create_tensor(tn(LLM_TENSOR_CLS, "bias"), {n_embd}, 0);
        cls_out = create_tensor(tn(LLM_TENSOR_CLS_OUT, "weight"), {n_embd, 1}, 0);
        cls_out_b = create_tensor(tn(LLM_TENSOR_CLS_OUT, "bias"), {1}, 0);
    }
    for (int i = 0; i < n_layer; ++i) {
        if (d1_omni && i >= n_layer - d1_head_layers) {
            auto & layer = layers[i];
            const auto ff = hparams.n_ff(i);
            layer.attn_norm = create_tensor(tn(LLM_TENSOR_ATTN_NORM, "weight", i), {n_embd}, 0);
            layer.attn_norm_b = create_tensor(tn(LLM_TENSOR_ATTN_NORM, "bias", i), {n_embd}, 0);
            layer.wqkv = create_tensor(tn(LLM_TENSOR_ATTN_QKV, "weight", i), {n_embd, 3*n_embd}, 0);
            layer.wqkv_b = create_tensor(tn(LLM_TENSOR_ATTN_QKV, "bias", i), {3*n_embd}, 0);
            layer.wo = create_tensor(tn(LLM_TENSOR_ATTN_OUT, "weight", i), {n_embd,n_embd}, 0);
            layer.wo_b = create_tensor(tn(LLM_TENSOR_ATTN_OUT, "bias", i), {n_embd}, 0);
            layer.ffn_norm = create_tensor(tn(LLM_TENSOR_FFN_NORM, "weight", i), {n_embd}, 0);
            layer.ffn_norm_b = create_tensor(tn(LLM_TENSOR_FFN_NORM, "bias", i), {n_embd}, 0);
            layer.ffn_up = create_tensor(tn(LLM_TENSOR_FFN_UP, "weight", i), {n_embd,ff}, 0);
            layer.ffn_up_b = create_tensor(tn(LLM_TENSOR_FFN_UP, "bias", i), {ff}, 0);
            layer.ffn_down = create_tensor(tn(LLM_TENSOR_FFN_DOWN, "weight", i), {ff,n_embd}, 0);
            layer.ffn_down_b = create_tensor(tn(LLM_TENSOR_FFN_DOWN, "bias", i), {n_embd}, 0);
            continue;
        }''')
replace('    for (int il = 0; il < n_layer; ++il) {', '''    const auto & d1_model = static_cast<const llama_model_lfm2 &>(model);
    const int trunk_layers = n_layer - (d1_model.d1_omni ? d1_model.d1_head_layers : 0);
    for (int il = 0; il < trunk_layers; ++il) {''')
replace('    res->t_embd = cur;', '''    if (d1_model.d1_omni) {
        auto * type_ids = ggml_new_tensor_1d(ctx0, GGML_TYPE_I32, 1);
        ggml_set_input(type_ids);
        res->add_input(std::make_unique<d1_type_input>(type_ids));
        cur = ggml_add(ctx0, cur, ggml_get_rows(ctx0, model.type_embd, type_ids));
        auto * head_attn = build_attn_inp_no_cache();
        for (int il = trunk_layers; il < n_layer; ++il) {
            const auto & l = model.layers[il];
            auto * norm = build_norm(cur, l.attn_norm, l.attn_norm_b, LLM_NORM, il);
            auto [q,k,v] = build_qkv(l, norm, hparams.n_embd_head_k(), hparams.n_head(il), hparams.n_head_kv(il), il);
            auto * attn = build_attn(head_attn, l.wo, l.wo_b, nullptr, q,k,v, nullptr,nullptr,nullptr,
                                    1.0f/sqrtf(float(hparams.n_embd_head_k())), il);
            cur = ggml_add(ctx0, cur, attn);
            norm = build_norm(cur, l.ffn_norm, l.ffn_norm_b, LLM_NORM, il);
            auto * ff = ggml_add(ctx0, build_lora_mm(l.ffn_up, norm), l.ffn_up_b);
            ff = ggml_relu(ctx0, ff);
            ff = ggml_add(ctx0, build_lora_mm(l.ffn_down, ff), l.ffn_down_b);
            cur = ggml_add(ctx0, cur, ff);
        }
        if (inp_out_ids) cur = ggml_get_rows(ctx0, cur, inp_out_ids);
        cur = build_norm(cur, model.cls_norm, model.cls_norm_b, LLM_NORM, -1);
        cur = ggml_add(ctx0, build_lora_mm(model.cls, cur), model.cls_b);
        cur = ggml_gelu_erf(ctx0, cur);
        cur = ggml_add(ctx0, build_lora_mm(model.cls_out, cur), model.cls_out_b);
        cb(cur, "d1_option_scores", -1);
    }
    res->t_embd = cur;''')
p.write_text(s)
p = root / 'src/models/models.h'
s = p.read_text()
old = 'struct llama_model_lfm2 : public llama_model_base {\n'
assert old in s
s = s.replace(old, old+'    bool d1_omni = false;\n    uint32_t d1_head_layers = 0;\n',1)
p.write_text(s)
