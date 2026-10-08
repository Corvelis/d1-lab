#include "media.h"
#include "llama.h"
#include "clip.h"
#include "clip-model.h"
#include "mtmd-image.h"
#include "mtmd-helper.h"
#include "stb/stb_image.h"
#include <complex>
#include <cmath>
#include <stdexcept>
#include <algorithm>
#include <fstream>
#include <cstdlib>
#include <chrono>
#include "ggml-backend.h"
std::vector<float> d1_read_audio_file(const std::string & path);

static bool debug_tensor(ggml_tensor * t, bool ask, void *) {
    const char * directory=std::getenv("D1_DEBUG_TENSORS");
    if(!directory || t->type != GGML_TYPE_F32 || !ggml_is_contiguous(t) || !strlen(t->name)) return ask ? false : true;
    if(ask) return true;
    std::vector<float> values(ggml_nelements(t));
    ggml_backend_tensor_get(t,values.data(),0,values.size()*sizeof(float));
    std::string file=std::string(directory)+"/"+t->name;
    std::ofstream(file+".f32",std::ios::binary).write(reinterpret_cast<char *>(values.data()),values.size()*sizeof(float));
    std::ofstream shape(file+".shape"); for(int i=3;i>=0;--i) shape<<t->ne[i]<<" ";
    return true;
}
struct MediaImpl {
    clip_ctx * vision=nullptr, *audio=nullptr;
    mtmd_context * mtmd=nullptr;
    ~MediaImpl() { if(vision) clip_free(vision); if(audio) clip_free(audio); if(mtmd) mtmd_free(mtmd); }
};
Media::Media(const std::string & path, llama_model * model, bool omni, bool gpu) : impl(new MediaImpl) {
    if(omni) {
        clip_context_params p{}; p.use_gpu=gpu; p.flash_attn_type=CLIP_FLASH_ATTN_TYPE_DISABLED;
        if(std::getenv("D1_DEBUG_TENSORS")) p.cb_eval=debug_tensor;
        p.image_min_tokens=-1; p.image_max_tokens=-1; p.warmup=false;
        auto c=clip_init(path.c_str(),p); impl->vision=c.ctx_v; impl->audio=c.ctx_a;
        if(!impl->vision || !impl->audio) throw std::runtime_error("omniプロジェクターを読み込めませんでした");
    } else {
        auto p=mtmd_context_params_default(); p.use_gpu=gpu; p.warmup=false;
        impl->mtmd=mtmd_init_from_file(path.c_str(),model,p);
        if(!impl->mtmd) throw std::runtime_error("3B画像プロジェクターを読み込めませんでした");
    }
}
Media::~Media() = default;

static void fft(std::vector<std::complex<float>> & a) {
    const int n=a.size();
    for(int i=1,j=0;i<n;++i) { int bit=n>>1; for(;j&bit;bit>>=1) j^=bit; j^=bit; if(i<j) std::swap(a[i],a[j]); }
    for(int len=2;len<=n;len<<=1) {
        std::complex<float> step=std::polar(1.0f,float(-2*M_PI/len));
        for(int i=0;i<n;i+=len) { std::complex<float> w=1; for(int j=0;j<len/2;++j) { auto u=a[i+j],v=a[i+j+len/2]*w; a[i+j]=u+v; a[i+j+len/2]=u-v; w*=step; } }
    }
}
static clip_image_f32 mel(const std::vector<float> & samples) {
    const int frames=samples.size()/160, bins=128;
    std::vector<float> emphasized(samples.size()); emphasized[0]=samples[0];
    for(size_t i=1;i<samples.size();++i) emphasized[i]=samples[i]-0.97f*samples[i-1];
    std::vector<float> window(512,0);
    for(int i=0;i<400;++i) window[56+i]=0.5f-0.5f*std::cos(float(2*M_PI*i/399));
    const double step=std::log(6.4)/27, low=15, maximum=low+std::log(8.0)/step;
    std::vector<double> hz(bins+2);
    for(int i=0;i<bins+2;++i) { double m=maximum*i/(bins+1); hz[i]=m<low?m*(200.0/3):1000*std::exp((m-low)*step); }
    std::vector<float> filters(bins*257);
    for(int m=0;m<bins;++m) for(int b=0;b<257;++b) {
        double f=double(b)*16000/512;
        filters[m*257+b]=std::max(0.0,std::min((f-hz[m])/(hz[m+1]-hz[m]),(hz[m+2]-f)/(hz[m+2]-hz[m+1])))*2/(hz[m+2]-hz[m]);
    }
    std::vector<float> data(bins*frames), power(257);
    std::vector<std::complex<float>> buffer(512);
    for(int t=0;t<frames;++t) {
        for(int i=0;i<512;++i) { int at=t*160+i-256; buffer[i]=at>=0 && at<int(samples.size())?emphasized[at]*window[i]:0; }
        fft(buffer); for(int i=0;i<257;++i) power[i]=std::norm(buffer[i]);
        for(int m=0;m<bins;++m) { float sum=0; for(int b=0;b<257;++b) sum+=power[b]*filters[m*257+b]; data[m*frames+t]=std::log(sum+std::ldexp(1.0f,-24)); }
    }
    for(int m=0;m<bins;++m) {
        double mean=0; for(int t=0;t<frames;++t) mean+=data[m*frames+t]; mean/=frames;
        double variance=0; for(int t=0;t<frames;++t) { double d=data[m*frames+t]-mean; variance+=d*d; }
        double std=std::sqrt(variance/(frames-1))+1e-5;
        for(int t=0;t<frames;++t) data[m*frames+t]=(data[m*frames+t]-mean)/std;
    }
    clip_image_f32 result; result.set_size({frames,bins},false,true); result.cpy_buf(data); return result;
}
std::vector<float> Media::encode(const std::string & path, bool is_audio) {
    std::vector<float> output;
    if(is_audio) {
        auto samples=d1_read_audio_file(path); const size_t read=samples.size();
        if(read==0 || read>480000) throw std::runtime_error("音声は0〜30秒の範囲にしてください");
        samples.resize(read); seconds=double(read)/16000;
        for(auto x:samples) if(!std::isfinite(x)) throw std::runtime_error("音声に不正なサンプルが含まれています");
        if(samples.size()<8000) samples.resize(8000,0);
        auto image=mel(samples);
        output.resize(size_t(clip_n_output_tokens(impl->audio,&image))*clip_n_mmproj_embd(impl->audio));
        clip_image_f32_batch batch; batch.is_audio=true; batch.entries.push_back(image);
        if(!clip_image_batch_encode(impl->audio,4,&batch,output)) throw std::runtime_error("音声エンコーダーの実行に失敗しました");
    } else {
        int width,height,channels; auto * pixels=stbi_load(path.c_str(),&width,&height,&channels,3);
        if(!pixels) throw std::runtime_error("画像を読み込めません。PNG・JPEGを選択してください");
        clip_image_u8 image; image.set_size({width,height},false); image.cpy_buf(std::vector<uint8_t>(pixels,pixels+size_t(width)*height*3)); stbi_image_free(pixels);
        auto crops=mtmd_image_preprocessor_lfm2(impl->vision).preprocess(image);
        for(auto & crop:crops.entries) {
            std::vector<float> values(size_t(clip_n_output_tokens(impl->vision,&crop))*clip_n_mmproj_embd(impl->vision));
            if(!clip_image_encode(impl->vision,4,&crop,values)) throw std::runtime_error("画像エンコーダーの実行に失敗しました");
            output.insert(output.end(),values.begin(),values.end());
        }
        if(crops.has_overview()) {
            std::vector<float> values(size_t(clip_n_output_tokens(impl->vision,&crops.overview))*clip_n_mmproj_embd(impl->vision));
            if(!clip_image_encode(impl->vision,4,&crops.overview,values)) throw std::runtime_error("画像サムネイルの実行に失敗しました");
            output.insert(output.end(),values.begin(),values.end());
        }
    }
    if(output.empty()) throw std::runtime_error("メディアの埋め込みが空です");
    return output;
}
ImageEvaluation Media::evaluate_image(llama_context * context,const std::string & path,const std::string & prompt,int limit) {
    using clock = std::chrono::steady_clock;
    auto elapsed=[](clock::time_point start) { return std::chrono::duration<double,std::milli>(clock::now()-start).count(); };
    ImageEvaluation result;
    auto start=clock::now();
    auto wrapper=mtmd_helper_bitmap_init_from_file(impl->mtmd,path.c_str(),false,mtmd_helper_init_opt_default());
    if(!wrapper.bitmap) throw std::runtime_error("画像を読み込めませんでした");
    std::unique_ptr<mtmd_bitmap,decltype(&mtmd_bitmap_free)> bitmap(wrapper.bitmap,mtmd_bitmap_free);
    if(mtmd_bitmap_is_audio(bitmap.get())) throw std::runtime_error("3Bには画像を入力してください");
    auto * ptr=bitmap.get(); mtmd_input_text text{prompt.c_str(),prompt.size(),false,true};
    std::unique_ptr<mtmd_input_chunks,decltype(&mtmd_input_chunks_free)> chunks(mtmd_input_chunks_init(),mtmd_input_chunks_free);
    if(mtmd_tokenize(impl->mtmd,chunks.get(),&text,&ptr,1)!=0) throw std::runtime_error("画像入力の準備に失敗しました");
    result.tokens=mtmd_helper_get_n_tokens(chunks.get());
    if(result.tokens>size_t(limit)) throw std::runtime_error("画像を含む入力がコンテキスト上限を超えています");
    result.prepare_ms=elapsed(start);
    llama_pos past=0;
    const auto n=mtmd_input_chunks_size(chunks.get());
    for(size_t i=0;i<n;++i) {
        auto * chunk=mtmd_input_chunks_get(chunks.get(),i);
        int rc;
        if(mtmd_input_chunk_get_type(chunk)==MTMD_INPUT_CHUNK_TYPE_IMAGE) {
            result.media_tokens+=mtmd_input_chunk_get_n_tokens(chunk);
            start=clock::now();
            rc=mtmd_encode_chunk(impl->mtmd,chunk);
            result.encode_ms+=elapsed(start); // clip encoding synchronizes before returning its embeddings.
            if(rc!=0) throw std::runtime_error("画像エンコードに失敗しました");
            start=clock::now();
            rc=mtmd_helper_decode_image_chunk(impl->mtmd,context,chunk,mtmd_get_output_embd(impl->mtmd),past,0,512,&past,nullptr,nullptr);
        } else {
            start=clock::now();
            rc=mtmd_helper_eval_chunk_single(impl->mtmd,context,chunk,past,0,512,i==n-1,&past);
        }
        // GPU dispatch alone is not inference time: wait for the final command to finish.
        llama_synchronize(context);
        result.forward_ms+=elapsed(start);
        if(rc!=0) throw std::runtime_error("画像判定に失敗しました: "+std::to_string(rc));
    }
    return result;
}
