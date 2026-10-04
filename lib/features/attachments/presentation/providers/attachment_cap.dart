import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;

/// Cuánto puede bajar una página como mucho (decisión E de F30): 500 MB por
/// elemento, cambiable en Ajustes. Lo que una página ofrezca por encima del
/// tope queda afuera, con «Bajar el resto».
///
/// Mismo almacén que el tema y el idioma de la app: es una preferencia de
/// este teléfono, no un dato de la bóveda.
class AttachmentCapNotifier extends StateNotifier<int> {
  AttachmentCapNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_valid(prefs.getInt(_key)) ?? defaultBytes);

  static const _key = 'attachments_max_bytes_per_item';

  static const _megabyte = 1024 * 1024;

  /// El tope de fábrica: 500 MB.
  static const defaultBytes = 500 * _megabyte;

  /// Los topes que se ofrecen en Ajustes.
  static const choices = [
    100 * _megabyte,
    200 * _megabyte,
    500 * _megabyte,
    1024 * _megabyte,
    2048 * _megabyte,
  ];

  final SharedPreferences _prefs;

  /// Un valor guardado que no es uno de los que se ofrecen —de una versión
  /// futura, o tocado a mano— vuelve al de fábrica.
  static int? _valid(int? stored) =>
      stored != null && choices.contains(stored) ? stored : null;

  Future<void> setBytes(int bytes) async {
    if (!choices.contains(bytes)) {
      throw ArgumentError.value(bytes, 'bytes', 'No es un tope que se ofrece');
    }
    state = bytes;
    await _prefs.setInt(_key, bytes);
  }
}

final attachmentCapProvider = StateNotifierProvider<AttachmentCapNotifier, int>(
  (ref) => AttachmentCapNotifier(prefs: ref.watch(sharedPreferencesProvider)),
);
