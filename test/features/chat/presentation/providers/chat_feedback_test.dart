import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_feedback.dart';

/// El 👍/👎 de las respuestas (F42): queda en las preferencias del teléfono,
/// y en ningún otro lado.
void main() {
  Future<SharedPreferences> prefs([Map<String, Object> values = const {}]) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('marcar, cambiar y desmarcar; queda guardado para la próxima', () async {
    final store = await prefs();
    final feedback = ChatFeedbackNotifier(prefs: store);
    expect(feedback.state, isEmpty);

    await feedback.toggle('a', ChatFeedback.good);
    await feedback.toggle('b', ChatFeedback.bad);
    expect(feedback.state, {'a': ChatFeedback.good, 'b': ChatFeedback.bad});

    await feedback.toggle('a', ChatFeedback.bad);
    expect(feedback.state['a'], ChatFeedback.bad);
    await feedback.toggle('b', ChatFeedback.bad);
    expect(feedback.state.containsKey('b'), isFalse);

    // Otro arranque de la app lo lee de las preferencias.
    expect(ChatFeedbackNotifier(prefs: store).state, {'a': ChatFeedback.bad});
    expect(store.getString(ChatFeedbackNotifier.prefsKey), '{"a":"bad"}');
  });

  test('guarda las últimas: la más vieja se va', () async {
    final store = await prefs();
    final feedback = ChatFeedbackNotifier(prefs: store);
    for (var i = 0; i <= ChatFeedbackNotifier.maxEntries; i++) {
      await feedback.toggle('m$i', ChatFeedback.good);
    }
    expect(feedback.state, hasLength(ChatFeedbackNotifier.maxEntries));
    expect(feedback.state.containsKey('m0'), isFalse);
    expect(feedback.state.containsKey('m1'), isTrue);
    expect(
      ChatFeedbackNotifier(prefs: store).state,
      hasLength(ChatFeedbackNotifier.maxEntries),
    );
  });

  test('volver a marcar una la deja como la más nueva', () async {
    final store = await prefs();
    final feedback = ChatFeedbackNotifier(prefs: store);
    await feedback.toggle('vieja', ChatFeedback.good);
    await feedback.toggle('otra', ChatFeedback.good);
    await feedback.toggle('vieja', ChatFeedback.bad);
    expect(feedback.state.keys, ['otra', 'vieja']);
  });

  test('algo roto o de otra versión no tira abajo el chat', () async {
    for (final raw in ['no es json', '[1, 2]', '"texto"']) {
      final store = await prefs({ChatFeedbackNotifier.prefsKey: raw});
      expect(ChatFeedbackNotifier(prefs: store).state, isEmpty, reason: raw);
    }
    final store = await prefs({
      ChatFeedbackNotifier.prefsKey: '{"a":"good","b":"meh","c":3}',
    });
    expect(ChatFeedbackNotifier(prefs: store).state, {'a': ChatFeedback.good});
  });
}
