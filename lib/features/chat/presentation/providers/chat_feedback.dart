import 'dart:collection';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;

/// Lo que le pareció una respuesta a la persona (F42): 👍 o 👎.
enum ChatFeedback { good, bad }

/// Las calificaciones de las respuestas del chat (F42), por id de mensaje.
///
/// **Nunca salen del teléfono**: no se mandan a ningún proveedor ni servicio
/// —ni a Gemini, ni a OpenAI, ni a Claude, ni a la telemetría—. Son una nota
/// de la persona para sí misma, como las conversaciones fijadas
/// (`ChatPinsNotifier`), y viven en las mismas preferencias, no en la base:
/// así no hace falta una columna nueva ni subir la versión del esquema. Lo
/// que se pierde es que no viajan con una copia de la bóveda.
///
/// Guarda las últimas [maxEntries]: una respuesta borrada deja su id suelto,
/// que no molesta, y así la lista no crece para siempre.
class ChatFeedbackNotifier extends StateNotifier<Map<String, ChatFeedback>> {
  ChatFeedbackNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_read(prefs));

  static const prefsKey = 'chat_answer_feedback';

  /// Cuántas calificaciones se guardan, como mucho: las más viejas se van.
  static const maxEntries = 1000;

  final SharedPreferences _prefs;

  static Map<String, ChatFeedback> _read(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return const {};
    // Un valor que esta versión no entiende —o roto a mano— no puede tirar
    // abajo el chat: se empieza sin calificaciones, o sin las que no entiende.
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const {};
    }
    if (decoded is! Map<String, dynamic>) return const {};
    return LinkedHashMap.of({
      for (final MapEntry(:key, :value) in decoded.entries)
        if (ChatFeedback.values.asNameMap()[value] case final feedback?)
          key: feedback,
    });
  }

  /// Pone [feedback] a la respuesta [messageId]; si ya tenía esa misma, se
  /// la saca —tocar otra vez el pulgar marcado lo desmarca—.
  Future<void> toggle(String messageId, ChatFeedback feedback) async {
    final next = LinkedHashMap.of(state)..remove(messageId);
    if (state[messageId] != feedback) next[messageId] = feedback;
    while (next.length > maxEntries) {
      next.remove(next.keys.first);
    }
    state = next;
    await _prefs.setString(
      prefsKey,
      jsonEncode({
        for (final MapEntry(:key, :value) in next.entries) key: value.name,
      }),
    );
  }
}

final chatFeedbackProvider =
    StateNotifierProvider<ChatFeedbackNotifier, Map<String, ChatFeedback>>(
      (ref) =>
          ChatFeedbackNotifier(prefs: ref.watch(sharedPreferencesProvider)),
    );
