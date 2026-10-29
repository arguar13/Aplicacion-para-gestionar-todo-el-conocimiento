# `libsinapsis_sd.so`: stable-diffusion.cpp con la puerta de Sinapsis
# (`sinapsis_sd.h`), para dibujar en el teléfono (F43, «Exigente — en el
# teléfono»). Solo se compila con `-Psinapsis.imagenesEnElTelefono=true` (ver
# `android/app/build.gradle.kts`): sin eso la app se arma igual, y la sección
# «Exigente» no aparece porque no encuentra la biblioteca.
#
# stable-diffusion.cpp (MIT, https://github.com/leejet/stable-diffusion.cpp)
# va fijado a un commit —nadie puede cambiar lo que se compila— y se baja la
# primera vez que se arma, con su ggml. Con `SINAPSIS_SDCPP_SOURCE_DIR` se usa
# una copia local ya bajada (sin red), la misma versión.
#
# Solo el procesador: en Android, Vulkan se cierra en muchos teléfonos y anda
# más lento que el procesador; OpenCL solo sirve en GPUs Adreno, y el Dimensity
# 7200 tiene una Mali.

cmake_minimum_required(VERSION 3.22.1)
project(sinapsis_sd C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# La versión verificada el 2026-10-28: la etiqueta `master-1024-77b72a2`.
set(SINAPSIS_SDCPP_COMMIT 77b72a2efed78f55de26892c7e909cee001e8b83)
set(SINAPSIS_SDCPP_SOURCE_DIR "" CACHE PATH
    "Una copia local de stable-diffusion.cpp en el commit ${SINAPSIS_SDCPP_COMMIT}, con su ggml")

# Lo que no hace falta en una biblioteca para el teléfono.
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SD_WEBP OFF CACHE BOOL "" FORCE)
set(SD_WEBM OFF CACHE BOOL "" FORCE)
set(SD_VULKAN OFF CACHE BOOL "" FORCE)
set(SD_OPENCL OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE OFF CACHE BOOL "" FORCE)
# Lo que pide la guía de Android de stable-diffusion.cpp: sin OpenMP, ggml
# reparte el trabajo con sus propios hilos.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
# ARMv8.2 con producto punto y media precisión: lo que tienen todos los
# teléfonos con 8 GB o más (Cortex-A75 en adelante). La app lo comprueba en
# /proc/cpuinfo antes de ofrecerlo (`DeviceProfile.cpuSupported`): uno sin
# eso se cerraría al dibujar.
set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)

if(SINAPSIS_SDCPP_SOURCE_DIR)
    add_subdirectory(${SINAPSIS_SDCPP_SOURCE_DIR} sdcpp EXCLUDE_FROM_ALL)
else()
    include(FetchContent)
    FetchContent_Declare(
        stable_diffusion_cpp
        GIT_REPOSITORY https://github.com/leejet/stable-diffusion.cpp.git
        GIT_TAG ${SINAPSIS_SDCPP_COMMIT}
        GIT_SUBMODULES ggml
        GIT_PROGRESS TRUE
    )
    FetchContent_GetProperties(stable_diffusion_cpp)
    if(NOT stable_diffusion_cpp_POPULATED)
        FetchContent_Populate(stable_diffusion_cpp)
        add_subdirectory(${stable_diffusion_cpp_SOURCE_DIR} ${stable_diffusion_cpp_BINARY_DIR} EXCLUDE_FROM_ALL)
    endif()
endif()

add_library(sinapsis_sd SHARED sinapsis_sd.cpp)
target_link_libraries(sinapsis_sd PRIVATE stable-diffusion log)
# Solo se ve lo de `sinapsis_sd.h`: ni lo de stable-diffusion.cpp ni lo de
# ggml, que entran enteros (estáticos) en esta biblioteca.
set_target_properties(sinapsis_sd PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden)
target_link_options(sinapsis_sd PRIVATE
    "-Wl,--exclude-libs,ALL"
    "-Wl,--gc-sections"
    # Páginas de 16 KB: lo que exige Google Play desde Android 15.
    "-Wl,-z,max-page-size=16384")
