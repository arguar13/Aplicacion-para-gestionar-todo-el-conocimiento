// La puerta de Sinapsis a stable-diffusion.cpp (F43, «Exigente — en el
// teléfono»): cinco funciones con tipos simples, para que el lado Dart
// (`dart:ffi`, `lib/features/ai_models/data/on_device/sd_native.dart`) no
// dependa de la forma de las estructuras de stable-diffusion.cpp, que cambian
// de una versión a otra. Lo que cambie allá se ajusta acá, en C++, donde el
// compilador avisa; el lado Dart sigue igual.
//
// Todo se llama desde un solo hilo (el isolate que dibuja), salvo
// `sinapsis_sd_cancel`, que se llama desde otro mientras se dibuja.

#ifndef SINAPSIS_SD_H
#define SINAPSIS_SD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SINAPSIS_SD_API __attribute__((visibility("default")))

// La versión de esta puerta: sube si cambia alguna firma. Dart la compara
// con la suya antes de usar nada.
#define SINAPSIS_SD_ABI 1

// Los códigos de `sinapsis_sd_generate` y `sinapsis_sd_load`.
#define SINAPSIS_SD_OK 0
// El archivo del modelo no se pudo abrir o no es un modelo que entienda.
#define SINAPSIS_SD_ERR_LOAD 1
// stable-diffusion.cpp no devolvió ninguna imagen.
#define SINAPSIS_SD_ERR_GENERATE 2
// Se canceló a pedido.
#define SINAPSIS_SD_ERR_CANCELLED 3
// No alcanzó la memoria para reservar lo que hacía falta.
#define SINAPSIS_SD_ERR_MEMORY 4
// Un argumento que no tiene sentido (contexto nulo, tamaño inválido).
#define SINAPSIS_SD_ERR_ARGS 5

SINAPSIS_SD_API int32_t sinapsis_sd_abi(void);

// Carga el modelo de `model_path` con `threads` hilos (0: los núcleos
// físicos). Devuelve el contexto, o NULL con el motivo en `*error`.
SINAPSIS_SD_API void* sinapsis_sd_load(const char* model_path, int32_t threads, int32_t* error);

// Dibuja `prompt` en `width` x `height` (múltiplos de 64) con `steps` pasos y
// guía `cfg`, semilla `seed` (-1: al azar). Deja los píxeles RGB (3 bytes por
// píxel, fila por fila) en `*out_pixels`, que se libera con
// `sinapsis_sd_free_pixels`, y el tamaño real en `*out_width`/`*out_height`.
SINAPSIS_SD_API int32_t sinapsis_sd_generate(void* ctx,
                                             const char* prompt,
                                             int32_t width,
                                             int32_t height,
                                             int32_t steps,
                                             float cfg,
                                             int64_t seed,
                                             uint8_t** out_pixels,
                                             int32_t* out_width,
                                             int32_t* out_height);

SINAPSIS_SD_API void sinapsis_sd_free_pixels(uint8_t* pixels);

// Pide que la imagen en curso se corte cuanto antes. Desde cualquier hilo.
SINAPSIS_SD_API void sinapsis_sd_cancel(void* ctx);

SINAPSIS_SD_API void sinapsis_sd_free(void* ctx);

#ifdef __cplusplus
}
#endif

#endif  // SINAPSIS_SD_H
