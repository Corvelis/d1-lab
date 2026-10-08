#include "decision.h"
#include <iostream>
#include <string>
#include "nlohmann/json.hpp"
int main(int argc, char ** argv) {
    if(argc<2) { std::cerr<<"usage: d1-cli model.gguf [cpu|metal] [projector.gguf]\n"; return 2; }
    void * e=d1_create();
    nlohmann::json options={{"path",argv[1]},{"backend",argc>2?argv[2]:"metal"}};
    if(argc>3) options["projectorPath"]=argv[3];
    std::string load=options.dump();
    char * out=d1_load(e,load.c_str()); std::cout<<out<<std::endl; d1_free(out);
    std::string line; while(std::getline(std::cin,line)) { out=d1_run(e,line.c_str()); std::cout<<out<<std::endl; d1_free(out); }
    d1_destroy(e);
}
