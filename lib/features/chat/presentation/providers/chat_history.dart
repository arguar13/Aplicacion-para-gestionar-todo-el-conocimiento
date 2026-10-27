import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

/// Las conversaciones fijadas del panel (F42), por id.
///
/// Se guardan en las preferencias del teléfono y no en la base, a
/// propósito: fijar es una forma de mirar el historial —como fijar una
/// pestaña—, no algo de la conversación misma, y así no hace falta una
/// columna nueva ni subir la versión del esquema. Lo que se pierde es que lo
/// fijado no viaja con una copia de la bóveda a otro teléfono; si algún día
/// hace falta, pasa a una columna de `conversations` y estas se migran.
///
/// Una conversación borrada se saca de acá al borrarla ([unpin]); un id
/// que quedara suelto —por ejemplo, de una copia restaurada— no molesta: el
/// panel solo fija las que existen.
class ChatPinsNotifier extends StateNotifier<Set<String>> {
  ChatPinsNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super({...?prefs.getStringList(prefsKey)});

  static const prefsKey = 'chat_pinned_conversations';

  final SharedPreferences _prefs;

  bool isPinned(String id) => state.contains(id);

  /// Fija [id] si no lo estaba, y lo desfija si lo estaba.
  Future<void> toggle(String id) => isPinned(id) ? unpin(id) : pin(id);

  Future<void> pin(String id) async {
    if (isPinned(id)) return;
    state = {...state, id};
    await _prefs.setStringList(prefsKey, state.toList());
  }

  Future<void> unpin(String id) async {
    if (!isPinned(id)) return;
    state = {...state}..remove(id);
    await _prefs.setStringList(prefsKey, state.toList());
  }
}

final chatPinsProvider = StateNotifierProvider<ChatPinsNotifier, Set<String>>(
  (ref) => ChatPinsNotifier(prefs: ref.watch(sharedPreferencesProvider)),
);

/// Todas las conversaciones guardadas, de los dos modos, la última usada
/// primero (F42): el panel las muestra juntas, cada una con su modo. Cada
/// modo sigue guardando su propio historial (decisión 26); lo que cambia es
/// que ya no hace falta pasar de modo para encontrar una.
final chatHistoryProvider =
    Provider.autoDispose<AsyncValue<List<ChatConversation>>>((ref) {
      final vault = ref.watch(
        chatConversationsProvider(ChatConversationMode.vault),
      );
      final free = ref.watch(
        chatConversationsProvider(ChatConversationMode.free),
      );
      for (final side in [vault, free]) {
        if (side case AsyncError(:final error, :final stackTrace)) {
          return AsyncError(error, stackTrace);
        }
      }
      final vaultList = vault.valueOrNull;
      final freeList = free.valueOrNull;
      if (vaultList == null || freeList == null) return const AsyncLoading();
      return AsyncData(
        [...vaultList, ...freeList]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );
    });

/// Qué junta una sección del panel.
enum ChatHistorySectionKind { pinned, today, yesterday, day }

/// Una sección del panel de conversaciones: las fijadas, las de hoy, las de
/// ayer o las de un día anterior ([day]).
@immutable
class ChatHistorySection {
  const ChatHistorySection({
    required this.kind,
    required this.conversations,
    this.day,
  });

  final ChatHistorySectionKind kind;

  /// El día, a la medianoche local; solo en [ChatHistorySectionKind.day].
  final DateTime? day;

  final List<ChatConversation> conversations;
}

/// Arma las secciones del panel (F42): primero las fijadas y después una por
/// día, de la más reciente a la más vieja, cada una con sus conversaciones
/// en el orden en que llegan —el de [chatHistoryProvider]—.
///
/// [query] filtra por título sin mirar mayúsculas ni acentos: «revolucion»
/// encuentra «Revolución». Una conversación sin título solo aparece sin
/// filtro. Los días se cuentan en la hora del teléfono: lo de anoche a las
/// 23:50 es de ayer aunque haya pasado hace diez minutos.
List<ChatHistorySection> groupChatHistory(
  List<ChatConversation> conversations, {
  required Set<String> pinned,
  required DateTime now,
  String query = '',
}) {
  final needle = foldForSearch(query);
  final matching = needle.isEmpty
      ? conversations
      : [
          for (final c in conversations)
            if (foldForSearch(c.title ?? '').contains(needle)) c,
        ];

  final today = _localDay(now);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final pinnedOnes = <ChatConversation>[];
  final byDay = <DateTime, List<ChatConversation>>{};
  for (final conversation in matching) {
    if (pinned.contains(conversation.id)) {
      pinnedOnes.add(conversation);
      continue;
    }
    byDay
        .putIfAbsent(_localDay(conversation.updatedAt), () => [])
        .add(conversation);
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    if (pinnedOnes.isNotEmpty)
      ChatHistorySection(
        kind: ChatHistorySectionKind.pinned,
        conversations: pinnedOnes,
      ),
    for (final day in days)
      ChatHistorySection(
        kind: day == today
            ? ChatHistorySectionKind.today
            : day == yesterday
            ? ChatHistorySectionKind.yesterday
            : ChatHistorySectionKind.day,
        day: day,
        conversations: byDay[day]!,
      ),
  ];
}

DateTime _localDay(DateTime at) {
  final local = at.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// [text] como lo compara una persona que busca: en minúscula, sin acentos y
/// con un solo espacio entre palabras.
String foldForSearch(String text) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final unit in text.runes) {
    final folded = foldWordChar(unit);
    if (folded == null) {
      pendingSpace = buffer.isNotEmpty;
      continue;
    }
    if (pendingSpace) buffer.write(' ');
    pendingSpace = false;
    buffer.write(folded);
  }
  return buffer.toString();
}
