#include <dlfcn.h>
#include <string.h>
#include "napi/native_api.h"
#define LOG_TAG "BlazorHybrid"
#include "hilog/log.h"

extern "C" void RegisterEntryModule(void);

static void* LoadEntryLibrary(void)
{
    Dl_info info = {};
    if (dladdr((void*)&LoadEntryLibrary, &info) != 0 && info.dli_fname != nullptr) {
        const char* slash = strrchr(info.dli_fname, '/');
        if (slash != nullptr) {
            char path[4096] = {};
            size_t directoryLength = (size_t)(slash - info.dli_fname) + 1;
            const char* entryName = "Entry.so";
            size_t entryNameLength = strlen(entryName);
            if (directoryLength + entryNameLength < sizeof(path)) {
                memcpy(path, info.dli_fname, directoryLength);
                memcpy(path + directoryLength, entryName, entryNameLength + 1);
                void* handle = dlopen(path, RTLD_NOW);
                if (handle != nullptr) {
                    return handle;
                }
            }
        }
    }

    return dlopen("Entry.so", RTLD_NOW);
}

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    void* handle = LoadEntryLibrary();
    if (handle == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Unable to load Entry.so: %{public}s", dlerror());
        return;
    }

    auto func = (void(*)())dlsym(handle, "RegisterEntryModule");
    if (func == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Unable to resolve RegisterEntryModule: %{public}s", dlerror());
        return;
    }
    func();
}
