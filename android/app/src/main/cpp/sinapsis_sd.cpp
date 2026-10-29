// Ver sinapsis_sd.h.

#include "sinapsis_sd.h"

#include <android/log.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <new>

#include "stable-diffusion.h"

namespace {

constexpr const char* kTag = "SinapsisSD";

// Lo que Dart tiene como «contexto»: el de stable-diffusion.cpp y la marca de
// cancelado propia. La propia hace falta porque `generate_image` borra la de
// stable-diffusion.cpp al empezar: una cancelación que llega justo antes se
// perdería.
struct Session {
    sd_ctx_t* sd = nullptr;
    std::atomic<bool> cancelled{false};
};

// La sesión que está dibujando, para el aviso de avance (que
// stable-diffusion.cpp registra para todo el proceso, no por contexto).
std::atomic<Session*> g_drawing{nullptr};

void OnLog(enum sd_log_level_t level, const char* text, void*) {
    if (text == nullptr) return;
    const int priority = level == SD_LOG_ERROR  ? ANDROID_LOG_ERROR
                         : level == SD_LOG_WARN ? ANDROID_LOG_WARN
                                                : ANDROID_LOG_DEBUG;
    __android_log_write(priority, kTag, text);
}

// En cada paso: si se pidió cortar, se le vuelve a decir. Así ninguna
// cancelación se pierde aunque haya llegado antes de que empezara a dibujar.
void OnProgress(int, int, float, void*) {
    Session* session = g_drawing.load();
    if (session != nullptr && session->cancelled.load()) {
        sd_cancel_generation(session->sd, SD_CANCEL_ALL);
    }
}

}  // namespace

extern "C" {

int32_t sinapsis_sd_abi(void) { return SINAPSIS_SD_ABI; }

void* sinapsis_sd_load(const char* model_path, int32_t threads, int32_t* error) {
    if (error != nullptr) *error = SINAPSIS_SD_OK;
    if (model_path == nullptr) {
        if (error != nullptr) *error = SINAPSIS_SD_ERR_ARGS;
        return nullptr;
    }
    sd_set_log_callback(OnLog, nullptr);
    sd_set_progress_callback(OnProgress, nullptr);

    Session* session = new (std::nothrow) Session();
    if (session == nullptr) {
        if (error != nullptr) *error = SINAPSIS_SD_ERR_MEMORY;
        return nullptr;
    }
    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.model_path = model_path;
    if (threads > 0) params.n_threads = threads;
    // Los pesos se leen del archivo a medida que hacen falta, sin una copia
    // entera en la memoria: en el teléfono, la memoria es lo que alcanza o no.
    params.enable_mmap = true;
    try {
        session->sd = new_sd_ctx(&params);
    } catch (const std::bad_alloc&) {
        session->sd = nullptr;
        if (error != nullptr) *error = SINAPSIS_SD_ERR_MEMORY;
        delete session;
        return nullptr;
    }
    if (session->sd == nullptr) {
        if (error != nullptr) *error = SINAPSIS_SD_ERR_LOAD;
        delete session;
        return nullptr;
    }
    return session;
}

int32_t sinapsis_sd_generate(void* ctx,
                             const char* prompt,
                             int32_t width,
                             int32_t height,
                             int32_t steps,
                             float cfg,
                             int64_t seed,
                             uint8_t** out_pixels,
                             int32_t* out_width,
                             int32_t* out_height) {
    auto* session = static_cast<Session*>(ctx);
    if (session == nullptr || session->sd == nullptr || prompt == nullptr || out_pixels == nullptr ||
        width <= 0 || height <= 0 || width % 64 != 0 || height % 64 != 0 || steps <= 0) {
        return SINAPSIS_SD_ERR_ARGS;
    }
    *out_pixels = nullptr;
    if (session->cancelled.exchange(false)) return SINAPSIS_SD_ERR_CANCELLED;

    sd_img_gen_params_t params;
    sd_img_gen_params_init(&params);
    params.prompt = prompt;
    params.negative_prompt = "";
    params.width = width;
    params.height = height;
    params.seed = seed;
    params.batch_count = 1;
    params.sample_params.sample_steps = steps;
    params.sample_params.guidance.txt_cfg = cfg;

    g_drawing.store(session);
    sd_image_generation_result_t* result = nullptr;
    bool ok = false;
    try {
        ok = generate_image(session->sd, &params, &result);
    } catch (const std::bad_alloc&) {
        g_drawing.store(nullptr);
        if (result != nullptr) free_sd_image_generation_result(result);
        return SINAPSIS_SD_ERR_MEMORY;
    }
    g_drawing.store(nullptr);
    const bool cancelled = session->cancelled.exchange(false);

    int32_t code = SINAPSIS_SD_OK;
    if (cancelled) {
        code = SINAPSIS_SD_ERR_CANCELLED;
    } else if (!ok || result == nullptr || result->count < 1 || result->items[0].image.data == nullptr) {
        code = SINAPSIS_SD_ERR_GENERATE;
    } else {
        const sd_image_t& image = result->items[0].image;
        const size_t pixels = static_cast<size_t>(image.width) * image.height;
        auto* rgb = static_cast<uint8_t*>(std::malloc(pixels * 3));
        if (rgb == nullptr) {
            code = SINAPSIS_SD_ERR_MEMORY;
        } else if (image.channel == 3) {
            std::memcpy(rgb, image.data, pixels * 3);
        } else {
            // Con transparencia (4 canales) o en grises (1): se lleva a RGB.
            for (size_t i = 0; i < pixels; ++i) {
                for (int c = 0; c < 3; ++c) {
                    const uint32_t from = image.channel >= 3 ? c : 0;
                    rgb[i * 3 + c] = image.data[i * image.channel + from];
                }
            }
        }
        if (rgb != nullptr) {
            *out_pixels = rgb;
            if (out_width != nullptr) *out_width = static_cast<int32_t>(image.width);
            if (out_height != nullptr) *out_height = static_cast<int32_t>(image.height);
        }
    }
    if (result != nullptr) free_sd_image_generation_result(result);
    return code;
}

void sinapsis_sd_free_pixels(uint8_t* pixels) { std::free(pixels); }

void sinapsis_sd_cancel(void* ctx) {
    auto* session = static_cast<Session*>(ctx);
    if (session == nullptr) return;
    session->cancelled.store(true);
    if (session->sd != nullptr) sd_cancel_generation(session->sd, SD_CANCEL_ALL);
}

void sinapsis_sd_free(void* ctx) {
    auto* session = static_cast<Session*>(ctx);
    if (session == nullptr) return;
    if (session->sd != nullptr) free_sd_ctx(session->sd);
    delete session;
}

}  // extern "C"
