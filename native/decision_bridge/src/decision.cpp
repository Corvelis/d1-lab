#include "decision.h"
#include "media.h"
#include "mtmd.h"
#include "llama.h"
#include "llama-ext.h"
#include "llama-model.h"
#include "ggml-backend.h"
#include "nlohmann/json.hpp"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <regex>
#include <stdexcept>
#include <string>
#include <vector>
#include <mutex>
#include <fstream>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

using json = nlohmann::ordered_json;
using clock_type = std::chrono::steady_clock;
static double ms(clock_type::time_point t) { return std::chrono::duration<double, std::milli>(clock_type::now()-t).count(); }
static json memory_snapshot() {
#ifdef __APPLE__
    task_vm_info_data_t info{};
    mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,reinterpret_cast<task_info_t>(&info),&count)==KERN_SUCCESS)
        return {{"physicalFootprintMB",double(info.phys_footprint)/1048576},
                {"residentMB",double(info.resident_size)/1048576},
                {"peakResidentMB",double(info.resident_size_peak)/1048576}};
#endif
    return json::object();
}
struct Engine {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    std::atomic<bool> cancelled{false};
    bool omni = false;
    uint32_t limit = 2048;
    json placement;
    std::unique_ptr<Media> media;
    std::vector<float> prefix;
    std::string media_path;
    bool audio = false;
    ~Engine() { unload(); }
    void unload() { media.reset(); prefix.clear(); media_path.clear(); if(context) llama_free(context); context=nullptr; if(model) llama_model_free(model); model=nullptr; }
};
static char * output(json j) { auto s=j.dump(); auto p=static_cast<char *>(malloc(s.size()+1)); if(!p) return nullptr; memcpy(p,s.c_str(),s.size()+1); return p; }
static char * error(const std::exception & e) { return output({{"error",e.what()}}); }
static bool abort_cb(void * data) { return static_cast<Engine *>(data)->cancelled.load(); }
static void check(Engine & e) { if(e.cancelled.load()) throw std::runtime_error("実行を中止しました"); }
static std::vector<llama_token> tokenize(Engine & e, const std::string & s, bool special=false) {
    auto vocab=llama_model_get_vocab(e.model);
    int n=llama_tokenize(vocab,s.data(),s.size(),nullptr,0,false,special);
    std::vector<llama_token> out(n < 0 ? -n : n);
    n=llama_tokenize(vocab,s.data(),s.size(),out.data(),out.size(),false,special);
    if(n<0) throw std::runtime_error("トークン化に失敗しました");
    out.resize(n); return out;
}
static llama_token special(Engine & e, const std::string & s) { auto t=tokenize(e,s,true); if(t.size()!=1) throw std::runtime_error("必要な特殊トークンがありません: "+s); return t[0]; }
static std::string escape(const std::string & s) { return std::regex_replace(s,std::regex("<\\|([A-Za-z0-9_]+)\\|>"),"<¦$1¦>"); }
static std::vector<double> softmax(const std::vector<double> & scores, double temperature) {
    if(scores.empty() || !(temperature>0)) throw std::runtime_error("判定出力が不正です");
    const double hi=*std::max_element(scores.begin(),scores.end());
    std::vector<double> p; double sum=0;
    for(auto v:scores) { if(!std::isfinite(v)) throw std::runtime_error("判定値が有限値ではありません"); p.push_back(std::exp((v-hi)/temperature)); sum+=p.back(); }
    for(auto & v:p) v/=sum;
    return p;
}
struct Question { std::string type, instructions; std::vector<std::string> labels, descriptions; };
static Question question(const json & j) {
    Question q{j.at("type").get<std::string>(),j.at("instructions").get<std::string>(),{}, {}};
    if(q.instructions.empty()) throw std::runtime_error("判定指示を入力してください");
    if(q.type=="noul") { q.labels={"No","Yes"}; q.descriptions={"no, the statement does not hold","yes, the statement holds"}; }
    else if(q.type=="choice") {
        for(auto & item:j.at("options")) { q.labels.push_back(item.at("name")); q.descriptions.push_back(item.value("description",std::string{})); }
    } else if(q.type=="score") {
        int i=0; for(auto & item:j.at("levels")) { q.labels.push_back(std::to_string(i++)); q.descriptions.push_back(item.get<std::string>()); }
    } else throw std::runtime_error("質問の種類が不正です");
    if(q.labels.size()<2 || q.labels.size()>(q.type=="score"?10:26)) throw std::runtime_error("選択肢は2〜26個、評価段階は2〜10個にしてください");
    for(auto & l:q.labels) if(l.empty()) throw std::runtime_error("空の選択肢があります");
    auto names=q.labels; std::sort(names.begin(),names.end());
    if(std::adjacent_find(names.begin(),names.end())!=names.end()) throw std::runtime_error("選択肢の名前が重複しています");
    return q;
}
static json run_question(Engine & e, const std::string & state, const Question & q, bool calibrated) {
    check(e);
    llama_memory_clear(llama_get_memory(e.context),true);
    auto start=clock_type::now();
    double prepare_ms=0, forward_ms=0, encode_ms=0;
    std::vector<llama_token> ids; std::vector<int> markers;
    std::vector<std::string> codes;
    json warnings=json::array();
    if(e.omni) {
        const int render_limit=!e.media_path.empty() && !e.audio ? std::min(896u,e.limit) : e.limit;
        const int k=q.labels.size(), budget=std::max(96,std::min(k*24+32,render_limit/2)), per=std::max(2,(budget-3*k)/k);
        std::vector<llama_token> block{special(e,"<|reserved_8|>")};
        auto inst=tokenize(e,escape(q.instructions));
        if(int(inst.size())>std::max(16,budget)-1) throw std::runtime_error("omniの判定指示が長すぎます。指示を短くしてください");
        block.insert(block.end(),inst.begin(),inst.end());
        for(int i=0;i<k;++i) {
            std::string opt=q.type=="choice" ? (e.audio ? "option_"+std::string(i<10?"00":"0")+std::to_string(i)+": "+(q.descriptions[i].empty()?q.labels[i]:q.descriptions[i]) : q.labels[i]+(q.descriptions[i].empty()?"":": "+q.descriptions[i])) : q.type=="score" ? "level "+std::to_string(i)+": "+q.descriptions[i] : (e.media_path.empty() ? (i==0?"false: ":"true: ")+q.descriptions[i] : (i==0?"false: no":"true: yes"));
            auto ts=tokenize(e,escape(" "+opt));
            if(int(ts.size())>per) throw std::runtime_error("omniの選択肢が長すぎます（1候補 "+std::to_string(per)+"トークンまで）。説明を短くしてください");
            markers.push_back(block.size()+1);
            block.push_back(special(e,"<|reserved_9|>")); block.push_back(special(e,"<|mask|>"));
            block.insert(block.end(),ts.begin(),ts.end()); block.push_back(special(e,"<|reserved_10|>"));
        }
        block.push_back(special(e,"<|reserved_11|>"));
        auto st=tokenize(e,escape(state));
        ids={llama_vocab_bos(llama_model_get_vocab(e.model)),special(e,"<|reserved_7|>")};
        ids.insert(ids.end(),st.begin(),st.end());
        for(auto & m:markers) m+=ids.size();
        ids.insert(ids.end(),block.begin(),block.end());
    } else {
        std::string body=q.instructions+"\n\n";
        if(q.type=="choice") {
            body+="Options:\n";
            bool identity=std::all_of(q.labels.begin(),q.labels.end(),[](const std::string & s){return s.size()==1 && s[0]>='A' && s[0]<='Z';});
            for(size_t i=0;i<q.labels.size();++i) { auto c=identity?q.labels[i]:std::string(1,char('A'+i)); codes.push_back(c); body+=c+" "+(q.descriptions[i].empty()?q.labels[i]:q.descriptions[i])+"\n"; }
            body+="\nReply with the option code only.";
        } else if(q.type=="score") {
            for(size_t i=0;i<q.labels.size();++i) { codes.push_back(q.labels[i]); body+=q.labels[i]+" "+q.descriptions[i]+"\n"; }
            body+="\nReply with a single digit 0-"+q.labels.back()+" only.";
        } else body+="Reply with yes or no only.";
        ids=tokenize(e,"<|im_start|>user\n"+state+"\n\n\nQUESTION:\n"+body+"<|im_end|>\n<|im_start|>assistant\n",true);
        const auto bos=llama_vocab_bos(llama_model_get_vocab(e.model));
        if(bos>=0) ids.insert(ids.begin(),bos);
    }
    const size_t prefix_count=e.prefix.size()/llama_model_n_embd_inp(e.model);
    size_t token_count=ids.size()+prefix_count;
    size_t media_tokens=prefix_count;
    if(token_count>e.limit || (e.omni && !e.media_path.empty() && !e.audio && ids.size()>896)) throw std::runtime_error("入力がコンテキスト上限を超えています（画像＋omniのテキストは896トークンまで）");
    std::vector<double> scores;
    if(e.omni) {
        auto * batch=llama_batch_ext_init(e.context);
        if(!batch) throw std::runtime_error("バッチを確保できませんでした");
        for(size_t i=0;i<prefix_count;++i) {
            llama_embd embd{e.prefix.data()+i*llama_model_n_embd_inp(e.model),1,size_t(llama_model_n_embd_inp(e.model))};
            int idx=llama_batch_ext_add_embd(batch,0,embd); llama_pos pos=i;
            llama_batch_ext_set_pos(batch,idx,&pos); llama_batch_ext_set_output_embd(batch,idx,false);
        }
        for(size_t i=0;i<ids.size();++i) {
            int idx=llama_batch_ext_add_token(batch,0,ids[i]); llama_pos pos=i+prefix_count;
            llama_batch_ext_set_pos(batch,idx,&pos);
            llama_batch_ext_set_output_embd(batch,idx,std::find(markers.begin(),markers.end(),int(i))!=markers.end());
        }
        auto type=q.type=="noul"?LLAMA_DECISION_ORDER_QUESTION_NOUL:q.type=="score"?LLAMA_DECISION_ORDER_QUESTION_SCORE:LLAMA_DECISION_ORDER_QUESTION_CHOICE;
        llama_batch_ext_set_decision_order(batch,0,type);
        prepare_ms=ms(start);
        auto forward_start=clock_type::now();
        int rc=llama_process(e.context,LLAMA_PROCESS_TYPE_DECODE,batch);
        llama_synchronize(e.context);
        forward_ms=ms(forward_start);
        llama_batch_ext_free(batch); check(e);
        if(rc!=0) throw std::runtime_error("omni推論に失敗しました: "+std::to_string(rc));
        for(auto m:markers) { auto * s=llama_get_embeddings_ith(e.context,m+prefix_count); if(!s) throw std::runtime_error("判定ヘッドの出力がありません"); scores.push_back(s[0]); }
    } else {
        if(!e.media_path.empty()) {
            std::string prompt;
            const auto * vocab=llama_model_get_vocab(e.model);
            for(auto id:ids) { char buffer[512]; int n=llama_token_to_piece(vocab,id,buffer,sizeof(buffer),0,true); if(n<0) throw std::runtime_error("入力の復元に失敗しました"); prompt.append(buffer,n); }
            const auto at=prompt.find("user\n");
            prompt.insert(at+5,mtmd_default_marker());
            prepare_ms=ms(start);
            auto image=e.media->evaluate_image(e.context,e.media_path,prompt,e.limit);
            token_count=image.tokens; media_tokens=image.media_tokens;
            prepare_ms+=image.prepare_ms; encode_ms=image.encode_ms; forward_ms=image.forward_ms;
        } else {
        const size_t step=512;
        auto batch=llama_batch_init(step,0,1);
        prepare_ms=ms(start);
        for(size_t at=0;at<ids.size();at+=step) {
            auto batch_start=clock_type::now();
            check(e); batch.n_tokens=std::min(step,ids.size()-at);
            for(int i=0;i<batch.n_tokens;++i) { batch.token[i]=ids[at+i]; batch.pos[i]=at+i; batch.n_seq_id[i]=1; batch.seq_id[i][0]=0; batch.logits[i]=at+i==ids.size()-1; }
            prepare_ms+=ms(batch_start);
            auto forward_start=clock_type::now();
            int rc=llama_decode(e.context,batch);
            llama_synchronize(e.context);
            forward_ms+=ms(forward_start);
            if(rc!=0) { llama_batch_free(batch); check(e); throw std::runtime_error("3B推論に失敗しました: "+std::to_string(rc)); }
        }
        llama_batch_free(batch); check(e);
        }
        auto logits=llama_get_logits_ith(e.context,-1);
        if(!logits) throw std::runtime_error("回答位置のlogitsがありません");
        std::vector<std::vector<std::string>> aliases;
        if(q.type=="noul") aliases={{"no","No","NO"},{"yes","Yes","YES"}};
        else for(auto & c:codes) aliases.push_back(q.type=="score"?std::vector<std::string>{c}:std::vector<std::string>{c," "+c});
        for(auto & group:aliases) {
            double v=-INFINITY;
            for(auto & alias:group) { auto t=tokenize(e,alias); if(t.size()==1) v=std::max(v,double(logits[t[0]])); }
            scores.push_back(v);
        }
    }
    double temperature=1;
    if(e.omni && calibrated && e.media_path.empty()) {
        const int k=q.labels.size();
        std::string bucket=k==2?"2":k<=5?"3_5":k<=10?"6_10":"11";
        std::string key="lfm2.decision.temperature."+q.type+"."+bucket;
        char value[128]; if(llama_model_meta_val_str(e.model,key.c_str(),value,sizeof(value))>0) temperature=std::stod(value);
    }
    auto p=softmax(scores,temperature); auto best=std::max_element(p.begin(),p.end())-p.begin();
    json probs=json::array(); for(size_t i=0;i<p.size();++i) probs.push_back({{"label",q.labels[i]},{"description",q.descriptions[i]},{"probability",p[i]},{"logit",scores[i]}});
    double expected=0; for(size_t i=0;i<p.size();++i) expected+=i*p[i];
    const double elapsed=ms(start);
    json result={{"type",q.type},{"instructions",q.instructions},{"selected",q.labels[best]},{"probabilities",probs},{"yesProbability",q.type=="noul"?json(p[1]):json(nullptr)},{"score",q.type=="score"?json(expected):json(nullptr)},{"confidence",p[best]},{"temperature",temperature},{"tokens",token_count},{"inferenceMs",elapsed},{"warnings",warnings},
        {"textTokens",token_count-media_tokens},{"mediaTokens",media_tokens},{"inputPrepareMs",prepare_ms},{"mediaEncodeMs",encode_ms},{"forwardMs",forward_ms},
        {"postprocessMs",std::max(0.0,elapsed-prepare_ms-encode_ms-forward_ms)},
        {"inputTokPerSec",forward_ms>0?json(token_count*1000.0/forward_ms):json(nullptr)},
        {"throughputKind",e.omni?"encoder-head":"prefill"}};
    if(std::getenv("D1_DEBUG_TOKENS")) { result["debugTokenIds"]=ids; result["debugMarkers"]=markers; }
    return result;
}
extern "C" {
void * d1_create() { return new Engine; }
void d1_destroy(void * p) { delete static_cast<Engine *>(p); }
void d1_free(char * p) { free(p); }
void d1_cancel(void * p) { static_cast<Engine *>(p)->cancelled.store(true); }
void d1_unload(void * p) { static_cast<Engine *>(p)->unload(); }
char * d1_load(void * p, const char * text) {
    auto & e=*static_cast<Engine *>(p); e.cancelled.store(false);
    try {
        auto j=json::parse(text); e.unload(); auto start=clock_type::now();
        static std::once_flag once; std::call_once(once,[]{llama_backend_init();});
        bool metal=j.value("backend",std::string("metal"))=="metal";
        if(metal && !ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU)) throw std::runtime_error("Metal GPUが利用できません。CPUを明示的に選択してください");
        auto params=llama_model_default_params(); params.n_gpu_layers=metal?999:0;
        ggml_backend_dev_t devices[]={metal?ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU):ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU),nullptr};
        params.devices=devices;
        params.progress_callback=[](float,void * data){ return !static_cast<Engine *>(data)->cancelled.load(); };
        params.progress_callback_user_data=&e;
        e.model=llama_model_load_from_file(j.at("path").get<std::string>().c_str(),params);
        check(e);
        if(!e.model) throw std::runtime_error("GGUFを読み込めませんでした。モデルとチェックサムを確認してください");
        char type[64]{};
        if(llama_model_meta_val_str(e.model,"lfm2.decision.type",type,sizeof(type))<=0) throw std::runtime_error("d1専用GGUFを選択してください");
        const std::string decision_type(type);
        e.omni=decision_type=="d1omni" || decision_type=="lfm2-d1-omni";
        if(decision_type!="d1" && decision_type!="lfm2-d1" && !e.omni) throw std::runtime_error("d1専用GGUFを選択してください");
        e.limit=j.value("contextTokens",2048u);
        if(e.limit<128 || e.limit>4096) throw std::runtime_error("コンテキスト上限は128〜4096にしてください");
        auto ctx=llama_context_default_params(); ctx.n_ctx=e.limit; ctx.n_batch=e.omni?e.limit:512; ctx.n_ubatch=e.omni?e.limit:128;
        ctx.n_threads=4; ctx.n_threads_batch=4; ctx.embeddings=e.omni; ctx.pooling_type=LLAMA_POOLING_TYPE_NONE;
        ctx.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_DISABLED; ctx.abort_callback=abort_cb; ctx.abort_callback_data=&e;
        ctx.op_offload=metal;
        e.context=llama_init_from_model(e.model,ctx); check(e);
        if(!e.context) throw std::runtime_error("推論コンテキストを確保できませんでした");
        auto projector=j.value("projectorPath",std::string{});
        if(!projector.empty()) e.media=std::make_unique<Media>(projector,e.model,e.omni,metal);
        int gpu=0,cpu=0;
        for(auto & entry:llama_internal_get_tensor_map(e.model)) {
            auto * t=entry.second; if(!t->buffer) continue;
            auto dev=ggml_backend_buft_get_device(ggml_backend_buffer_get_type(t->buffer));
            if(dev && ggml_backend_dev_type(dev)==GGML_BACKEND_DEVICE_TYPE_GPU) ++gpu; else ++cpu;
        }
        if(metal && gpu==0) throw std::runtime_error("GPUに重みが配置されませんでした");
        e.placement={{"requested",metal?"Metal":"CPU"},{"actual",gpu>0?(cpu>0?"Metal + CPU":"Metal"):"CPU"},{"gpuTensors",gpu},{"cpuTensors",cpu},{"runtimeCommit","18b5f8b1862ebfe0f1c33d2355b81a54d2fec867+d1-lab-v2"}};
        return output({{"model",e.omni?"d1-omni-600M":"d1-3B"},{"loadMs",ms(start)},{"placement",e.placement},{"contextTokens",e.limit},{"processMemory",memory_snapshot()}});
    } catch(const std::exception & ex) { e.unload(); return error(ex); }
}
char * d1_run(void * p, const char * text) {
    auto & e=*static_cast<Engine *>(p); e.cancelled.store(false);
    try {
        if(!e.context) throw std::runtime_error("モデルを読み込んでください");
        auto j=json::parse(text); auto start=clock_type::now();
        e.prefix.clear(); e.media_path=j.value("mediaPath",std::string{}); e.audio=j.value("mediaType",std::string{})=="audio";
        double encode_ms=0;
        if(!e.media_path.empty()) {
            if(!e.media) throw std::runtime_error("画像・音声用プロジェクターを取得してください");
            if(!e.omni && e.audio) throw std::runtime_error("音声入力はomniに切り替えてください");
            if(e.omni) { auto encoded=clock_type::now(); e.prefix=e.media->encode(e.media_path,e.audio); encode_ms=ms(encoded); check(e); }
        }
        std::string prefix_dump;
        if(const char * directory=std::getenv("D1_DEBUG_PREFIX_DIR"); directory && !e.prefix.empty()) {
            prefix_dump=std::string(directory)+(e.audio?"/audio-prefix.f32":"/image-prefix.f32");
            std::ofstream stream(prefix_dump,std::ios::binary); stream.write(reinterpret_cast<const char *>(e.prefix.data()),e.prefix.size()*sizeof(float));
        }
        json results=json::array();
        for(auto & q:j.at("questions")) results.push_back(run_question(e,j.at("state"),question(q),j.value("calibrated",true)));
        if(results.empty()) throw std::runtime_error("質問を追加してください");
        double forward_ms=0, prepare_ms=0, post_ms=0;
        size_t tokens=0, text_tokens=0, media_tokens=0;
        for(auto & r:results) {
            forward_ms+=r["forwardMs"].get<double>(); prepare_ms+=r["inputPrepareMs"].get<double>();
            post_ms+=r["postprocessMs"].get<double>(); encode_ms+=r["mediaEncodeMs"].get<double>();
            tokens+=r["tokens"].get<size_t>(); text_tokens+=r["textTokens"].get<size_t>(); media_tokens+=r["mediaTokens"].get<size_t>();
        }
        json result={{"model",e.omni?"d1-omni-600M":"d1-3B"},{"results",results},{"totalMs",ms(start)},{"mediaEncodeMs",encode_ms},{"prefixTokens",e.prefix.size()/llama_model_n_embd_inp(e.model)},{"audioSeconds",e.media?e.media->seconds:0},{"placement",e.placement},{"processMemory",memory_snapshot()}};
        result["metricsVersion"]=1;
        result["forwardMs"]=forward_ms; result["inputPrepareMs"]=prepare_ms; result["postprocessMs"]=post_ms;
        result["inputTokens"]=tokens; result["textTokens"]=text_tokens; result["mediaTokens"]=media_tokens;
        result["inputTokPerSec"]=forward_ms>0?json(tokens*1000.0/forward_ms):json(nullptr);
        result["throughputKind"]=e.omni?"encoder-head":"prefill";
        if(!prefix_dump.empty()) result["debugPrefixFile"]=prefix_dump;
        return output(result);
    } catch(const std::exception & ex) { return error(ex); }
}
}
