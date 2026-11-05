#include "decision.h"
#include <iostream>
#include <string>
#include "nlohmann/json.hpp"
int main(int argc, char ** argv) {
    if(argc<2) { std::cerr<<"usage: d1-cli model.gguf [cpu|metal] [projector.gguf|-] [load-options-json]\n"; return 2; }
    void * e=d1_create();
    nlohmann::json options={{"path",argv[1]},{"backend",argc>2?argv[2]:"metal"}};
    if(argc>3 && std::string(argv[3])!="-") options["projectorPath"]=argv[3];
    if(argc>4) {
        try { options.update(nlohmann::json::parse(argv[4])); }
        catch(const std::exception & ex) { std::cerr<<ex.what()<<std::endl; d1_destroy(e); return 2; }
    }
    std::string load=options.dump();
    char * out=d1_load(e,load.c_str());
    if(!out) { d1_destroy(e); return 1; }
    const bool failed=nlohmann::json::parse(out).contains("error");
    std::cout<<out<<std::endl; d1_free(out);
    if(failed) { d1_destroy(e); return 1; }
    std::string line; while(std::getline(std::cin,line)) { out=d1_run(e,line.c_str()); std::cout<<out<<std::endl; d1_free(out); }
    d1_destroy(e);
}
