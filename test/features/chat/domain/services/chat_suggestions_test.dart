import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/domain/services/chat_greeting.dart';
import 'package:sinapsis/features/chat/domain/services/chat_suggestions.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_suggestions_provider.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';

void main() {
  group('las sugerencias del chat con la bóveda (F42)', () {
    test('con tres títulos y un tema: resumir el último, preguntar por el '
        'anterior, qué dice el tercero y el tema', () {
      expect(
        vaultChatSuggestions(
          recentTitles: ['Don Quijote', "Laudato si'", 'Roma'],
          topTopic: 'Historia',
        ),
        const [
          SummarizeItemSuggestion('Don Quijote'),
          QuizMeSuggestion("Laudato si'"),
          AskItemSuggestion('Roma'),
          ExploreTopicSuggestion('Historia'),
        ],
      );
    });

    test('con un solo título, resumir y preguntar son sobre ese', () {
      expect(vaultChatSuggestions(recentTitles: ['Roma']), const [
        SummarizeItemSuggestion('Roma'),
        QuizMeSuggestion('Roma'),
      ]);
    });

    test('con dos, no hay «qué dice» —no se repite un título—', () {
      expect(vaultChatSuggestions(recentTitles: ['A', 'B']), const [
        SummarizeItemSuggestion('A'),
        QuizMeSuggestion('B'),
      ]);
    });

    test('acotado a un cuaderno, su nombre en lugar del tema', () {
      expect(
        vaultChatSuggestions(
          recentTitles: ['A'],
          topTopic: 'Historia',
          notebookName: 'Tesis',
        ).last,
        const NotebookThemesSuggestion('Tesis'),
      );
    });

    test('los títulos vacíos o repetidos no cuentan, y se recortan', () {
      expect(
        vaultChatSuggestions(recentTitles: ['  Roma ', '', 'Roma', '   ']),
        const [SummarizeItemSuggestion('Roma'), QuizMeSuggestion('Roma')],
      );
    });

    test('sin nada guardado, solo el tema si hay; sin tema, nada', () {
      expect(
        vaultChatSuggestions(recentTitles: const [], topTopic: 'Historia'),
        const [ExploreTopicSuggestion('Historia')],
      );
      expect(
        vaultChatSuggestions(recentTitles: const [], topTopic: ' '),
        isEmpty,
      );
    });

    test('nunca más de cuatro', () {
      expect(
        vaultChatSuggestions(
          recentTitles: ['A', 'B', 'C', 'D', 'E'],
          topTopic: 'T',
        ),
        hasLength(kMaxChatSuggestions),
      );
    });

    test('las que son una pregunta entera se mandan; las que se completan, '
        'no', () {
      expect(const SummarizeItemSuggestion('x').sendsAtOnce, isTrue);
      expect(const QuizMeSuggestion('x').sendsAtOnce, isTrue);
      expect(const ExploreTopicSuggestion('x').sendsAtOnce, isTrue);
      expect(const NotebookThemesSuggestion('x').sendsAtOnce, isTrue);
      expect(const AskItemSuggestion('x').sendsAtOnce, isFalse);
      for (final free in freeChatSuggestions) {
        expect(free.sendsAtOnce, isFalse);
      }
    });

    test('la conversación libre propone tres comienzos distintos', () {
      expect(
        freeChatSuggestions.map((s) => s.starter).toSet(),
        FreeChatStarter.values.toSet(),
      );
    });
  });

  group('el tema de la sugerencia (F42)', () {
    NotebookTopic topic(NotebookTopicKind kind, String name, int count) =>
        NotebookTopic(kind: kind, id: name, name: name, itemCount: count);

    test('el tema con más elementos, antes que cualquier etiqueta', () {
      expect(
        topNotebookTopic([
          topic(NotebookTopicKind.tag, 'etiqueta grande', 90),
          topic(NotebookTopicKind.space, 'Historia', 5),
          topic(NotebookTopicKind.space, 'Filosofía', 12),
          topic(NotebookTopicKind.space, 'Arte', 3),
        ]),
        'Filosofía',
      );
    });

    test('sin temas, la etiqueta con más; sin nada, ninguno', () {
      expect(
        topNotebookTopic([
          topic(NotebookTopicKind.tag, 'chica', 2),
          topic(NotebookTopicKind.tag, 'grande', 9),
        ]),
        'grande',
      );
      expect(topNotebookTopic(const []), isNull);
      expect(topNotebookTopic(null), isNull);
    });
  });

  group('el saludo según la hora (F42)', () {
    test('mañana de 5 a 12, tarde de 12 a 20, noche de 20 a 5', () {
      DayPart at(int hour, [int minute = 0]) =>
          dayPartOf(DateTime(2026, 10, 27, hour, minute));

      expect(at(4, 59), DayPart.evening);
      expect(at(5), DayPart.morning);
      expect(at(11, 59), DayPart.morning);
      expect(at(12), DayPart.afternoon);
      expect(at(19, 59), DayPart.afternoon);
      expect(at(20), DayPart.evening);
      expect(at(2), DayPart.evening);
    });
  });
}
