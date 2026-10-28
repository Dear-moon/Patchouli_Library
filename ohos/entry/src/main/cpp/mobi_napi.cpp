#include <napi/native_api.h>
#include <WenkuBookEngine.h>
#include <memory>
#include <new>
#include <string>
#include <vector>

namespace {
struct ImportJob {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string input;
    std::string output;
    int32_t status = 2;
};

napi_value Error(napi_env env, const char* message) {
    napi_value text = nullptr, error = nullptr;
    napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &text);
    napi_create_error(env, nullptr, text, &error);
    return error;
}

bool Path(napi_env env, napi_value value, std::string& path) {
    size_t length = 0, copied = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length == 0 || length >= 4096) return false;
    std::vector<char> bytes(length + 1);
    if (napi_get_value_string_utf8(env, value, bytes.data(), bytes.size(), &copied) != napi_ok || copied != length) return false;
    path.assign(bytes.data(), copied);
    return path.find('\0') == std::string::npos;
}

void Execute(napi_env, void* value) {
    auto* job = static_cast<ImportJob*>(value);
    job->status = wenku_export_mobi(job->input.c_str(), job->output.c_str());
}

void Complete(napi_env env, napi_status status, void* value) {
    std::unique_ptr<ImportJob> job(static_cast<ImportJob*>(value));
    napi_value result = nullptr;
    if (status == napi_ok && napi_create_int32(env, job->status, &result) == napi_ok) {
        napi_resolve_deferred(env, job->deferred, result);
    } else {
        napi_reject_deferred(env, job->deferred, Error(env, "Kindle conversion was interrupted"));
    }
    napi_delete_async_work(env, job->work);
}

napi_value ExtractKindle(napi_env env, napi_callback_info info) {
    size_t count = 2;
    napi_value args[2] = {nullptr, nullptr};
    auto job = std::unique_ptr<ImportJob>(new (std::nothrow) ImportJob());
    if (!job || napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 2 ||
        !Path(env, args[0], job->input) || !Path(env, args[1], job->output)) {
        napi_throw_type_error(env, nullptr, "Kindle conversion requires two bounded local paths");
        return nullptr;
    }
    napi_value promise = nullptr, name = nullptr;
    if (napi_create_promise(env, &job->deferred, &promise) != napi_ok) return nullptr;
    if (napi_create_string_utf8(env, "local-kindle-import", NAPI_AUTO_LENGTH, &name) != napi_ok ||
        napi_create_async_work(env, nullptr, name, Execute, Complete, job.get(), &job->work) != napi_ok ||
        napi_queue_async_work(env, job->work) != napi_ok) {
        if (job->work) napi_delete_async_work(env, job->work);
        napi_reject_deferred(env, job->deferred, Error(env, "Cannot start Kindle conversion"));
        return promise;
    }
    job.release(); // Complete owns the work item only after queueing succeeds.
    return promise;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor descriptor = {"extractKindle", nullptr, ExtractKindle, nullptr, nullptr, nullptr, napi_default, nullptr};
    napi_define_properties(env, exports, 1, &descriptor);
    return exports;
}
napi_module module = {1, 0, nullptr, Init, "wenku_book_engine", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterWenkuBookEngine() {
    napi_module_register(&module);
}
