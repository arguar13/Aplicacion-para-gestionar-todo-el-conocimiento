import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/keep_working/data/services/method_channel_background_settings.dart';
import 'package:sinapsis/features/keep_working/domain/services/background_settings.dart';

/// Los ajustes de segundo plano del sistema, solo en Android: en el resto no
/// hay nada que cierre la app con trabajo a medias, y la ayuda no se ofrece
/// ni aparece en Ajustes.
final backgroundSettingsProvider = Provider<BackgroundSettings?>(
  (ref) => kIsWeb || defaultTargetPlatform != TargetPlatform.android
      ? null
      : const MethodChannelBackgroundSettings(),
);

/// Si ya se ofreció la ayuda "Que siga con la app cerrada" (F29): se ofrece
/// una sola vez, la primera vez que hay trabajo largo con la app a la vista;
/// después queda en Ajustes.
class KeepWorkingHelpOffer {
  const KeepWorkingHelpOffer(this._prefs);

  static const _key = 'keep_working_help_offered';

  final SharedPreferences _prefs;

  bool get alreadyOffered => _prefs.getBool(_key) ?? false;

  Future<void> markOffered() => _prefs.setBool(_key, true);
}

final keepWorkingHelpOfferProvider = Provider<KeepWorkingHelpOffer>(
  (ref) => KeepWorkingHelpOffer(ref.watch(sharedPreferencesProvider)),
);
