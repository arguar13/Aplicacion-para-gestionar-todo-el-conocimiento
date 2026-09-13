//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audio_decoder/audio_decoder_plugin_c_api.h>
#include <desktop_drop/desktop_drop_plugin.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <sentry_flutter/sentry_flutter_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AudioDecoderPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioDecoderPluginCApi"));
  DesktopDropPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopDropPlugin"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  SentryFlutterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SentryFlutterPlugin"));
}
