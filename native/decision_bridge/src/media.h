#pragma once
#include <memory>
#include <string>
#include <vector>
struct llama_model;
struct llama_context;
struct MediaImpl;
struct ImageEvaluation {
    size_t tokens = 0, media_tokens = 0;
    double prepare_ms = 0, encode_ms = 0, forward_ms = 0;
};
struct Media {
    std::unique_ptr<MediaImpl> impl;
    Media(const std::string & path, llama_model * model, bool omni, bool gpu);
    ~Media();
    std::vector<float> encode(const std::string & path, bool audio);
    ImageEvaluation evaluate_image(llama_context * context, const std::string & path, const std::string & prompt, int limit);
    double seconds = 0;
};
