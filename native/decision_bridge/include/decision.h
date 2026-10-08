#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void * d1_create(void);
void d1_destroy(void * engine);
// All calls except cancel/free are serialized by the host. Returned UTF-8 JSON is caller-owned.
char * d1_load(void * engine, const char * json);
char * d1_run(void * engine, const char * json);
void d1_cancel(void * engine);
void d1_unload(void * engine);
void d1_free(char * json);
#ifdef __cplusplus
}
#endif
