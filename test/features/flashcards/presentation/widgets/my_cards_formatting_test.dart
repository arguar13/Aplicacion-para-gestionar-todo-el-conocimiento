import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/my_cards_formatting.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Los textos de «Mis tarjetas» (F31, ola 2, decisión 72): etapa, forma y
/// vencimiento, en español y en inglés.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  // Las 10:00 del 8 de octubre: el día de estudio va de las 4:00 de hoy a las
  // 4:00 de mañana.
  final now = DateTime(2026, 10, 8, 10);

  Flashcard card({
    DateTime? dueAt,
    int interval = 0,
    int repetitions = 0,
    int? step,
    bool suspended = false,
    FlashcardKind kind = FlashcardKind.freeRecall,
    String? groupId,
    int? clozeIndex,
    String front = 'pregunta',
    DateTime? lastReviewedAt,
  }) => Flashcard(
    id: 'c',
    itemId: 'i',
    front: front,
    back: 'respuesta',
    dueAt: dueAt ?? now,
    createdAt: DateTime(2026, 9),
    intervalDays: interval,
    repetitions: repetitions,
    learningStep: step,
    suspended: suspended,
    kind: kind,
    groupId: groupId,
    clozeIndex: clozeIndex,
    lastReviewedAt: lastReviewedAt,
  );

  group('cardStageLabel', () {
    test('cada etapa tiene su palabra', () {
      expect(cardStageLabel(es, card()), 'Nueva');
      expect(
        cardStageLabel(es, card(step: 0, lastReviewedAt: now)),
        'Aprendiendo',
      );
      expect(
        cardStageLabel(es, card(step: 0, interval: 3, lastReviewedAt: now)),
        'Reaprendiendo',
      );
      expect(cardStageLabel(es, card(interval: 20, repetitions: 3)), 'Joven');
      expect(cardStageLabel(es, card(interval: 21, repetitions: 3)), 'Madura');
    });

    test('una pausada es «Pausada» sea cual sea su etapa', () {
      expect(cardStageLabel(es, card(suspended: true)), 'Pausada');
      expect(
        cardStageLabel(es, card(suspended: true, interval: 90, repetitions: 4)),
        'Pausada',
      );
    });

    test('en inglés', () {
      expect(cardStageLabel(en, card()), 'New');
      expect(cardStageLabel(en, card(interval: 40, repetitions: 2)), 'Mature');
    });
  });

  group('cardDueLabel', () {
    String label(DateTime dueAt, {DateTime? at}) => cardDueLabel(
      es,
      card(dueAt: dueAt, interval: 5, repetitions: 2),
      at ?? now,
    );

    test('una nueva no tiene fecha', () {
      expect(cardDueLabel(es, card(), now), 'Sin programar');
    });

    test('hoy, mañana, en N días y atrasada', () {
      expect(label(DateTime(2026, 10, 8, 22)), 'Vence hoy');
      expect(label(DateTime(2026, 10, 9, 12)), 'Vence mañana');
      expect(label(DateTime(2026, 10, 13, 12)), 'Vence en 5 días');
      expect(label(DateTime(2026, 10, 7, 12)), 'Atrasada 1 día');
      expect(label(DateTime(2026, 10, 1, 12)), 'Atrasada 7 días');
    });

    test('se cuenta en días de estudio, no de calendario', () {
      // A las 2:00 del 9 todavía es el día de estudio del 8: lo que vence a
      // las 3:00 del 9 es de HOY, y lo de las 5:00 es de mañana.
      final lateNight = DateTime(2026, 10, 9, 2);
      expect(label(DateTime(2026, 10, 9, 3), at: lateNight), 'Vence hoy');
      expect(label(DateTime(2026, 10, 9, 5), at: lateNight), 'Vence mañana');
      // Y a las 4:30 ya cambió.
      final morning = DateTime(2026, 10, 9, 4, 30);
      expect(label(DateTime(2026, 10, 9, 3), at: morning), 'Atrasada 1 día');
      expect(label(DateTime(2026, 10, 9, 5), at: morning), 'Vence hoy');
    });

    test('en inglés', () {
      expect(
        cardDueLabel(
          en,
          card(dueAt: DateTime(2026, 10, 13, 12), interval: 5, repetitions: 2),
          now,
        ),
        'Due in 5 days',
      );
    });
  });

  group('cardShapeLabel', () {
    test('la forma común no se rotula', () {
      expect(cardShapeLabel(es, card()), isNull);
    });

    test('cada forma', () {
      expect(cardShapeLabel(es, card(kind: FlashcardKind.cloze)), 'Huecos');
      expect(
        cardShapeLabel(es, card(kind: FlashcardKind.typedAnswer)),
        'Escribir la respuesta',
      );
      expect(
        cardShapeLabel(es, card(kind: FlashcardKind.multipleChoice)),
        'Opción múltiple',
      );
      expect(
        cardShapeLabel(es, card(kind: FlashcardKind.trueFalse)),
        'Verdadero o falso',
      );
    });

    test('con hermanas', () {
      expect(cardShapeLabel(es, card(groupId: 'g')), 'Con hermanas');
      expect(
        cardShapeLabel(es, card(kind: FlashcardKind.cloze, groupId: 'g')),
        'Huecos, con hermanas',
      );
    });
  });

  group('cardListTitle', () {
    test('una común muestra su frente', () {
      expect(cardListTitle(card(front: '¿Qué es?')), '¿Qué es?');
    });

    test('una de huecos muestra su hueco tapado', () {
      final c = card(
        kind: FlashcardKind.cloze,
        clozeIndex: 2,
        front: 'El {{c1::Imperio}} cayó en {{c2::476}}',
      );
      expect(cardListTitle(c), 'El Imperio cayó en [...]');
    });

    test('un hueco que ya no existe cae al texto', () {
      final c = card(
        kind: FlashcardKind.cloze,
        clozeIndex: 5,
        front: 'El {{c1::Imperio}} cayó',
      );
      expect(cardListTitle(c), 'El {{c1::Imperio}} cayó');
    });
  });

  test('todos los estados y órdenes tienen rótulo en los dos idiomas', () {
    for (final status in CardBrowserStatus.values) {
      expect(statusFilterLabel(es, status), isNotEmpty);
      expect(statusFilterLabel(en, status), isNotEmpty);
    }
    for (final sort in CardBrowserSort.values) {
      expect(sortLabel(es, sort), isNotEmpty);
      expect(sortLabel(en, sort), isNotEmpty);
    }
    expect(statusFilterLabel(es, CardBrowserStatus.due), 'Por repasar');
    expect(sortLabel(es, CardBrowserSort.lapses), 'Olvidos');
  });
}
