import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_actions.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';

/// En qué está el texto de lo que espera en la Bandeja, y qué permite hacer
/// (F41): dos reglas puras, un solo lugar para la tarjeta, la lista, los
/// gestos y las teclas.
void main() {
  group('PendingText.of', () {
    test('con texto siempre está listo, aunque se esté volviendo a extraer o '
        'haya fallado: el de antes queda', () {
      for (final processing in ProcessingState.values) {
        expect(
          PendingText.of(hasText: true, processing: processing),
          PendingText.ready,
          reason: processing.name,
        );
      }
    });

    test('sin texto, lo dice el procesamiento', () {
      expect(
        PendingText.of(hasText: false, processing: ProcessingState.pending),
        PendingText.arriving,
      );
      expect(
        PendingText.of(hasText: false, processing: ProcessingState.processing),
        PendingText.arriving,
      );
      expect(
        PendingText.of(hasText: false, processing: ProcessingState.failed),
        PendingText.failed,
      );
      expect(
        PendingText.of(hasText: false, processing: ProcessingState.ready),
        PendingText.missing,
      );
    });

    test('solo «listo» está listo', () {
      expect(PendingText.values.where((text) => text.isReady), [
        PendingText.ready,
      ]);
    });
  });

  group('InboxActions.of', () {
    final now = DateTime(2026, 10, 27);

    KnowledgeItem item({String? text}) => KnowledgeItem(
      id: 'x',
      title: 'Una fuente',
      source: Source(id: 'x', kind: SourceKind.webPage, capturedAt: now),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        if (text != null)
          Rendition.text(
            id: 'texto',
            itemId: 'x',
            kind: RenditionKind.plainText,
            content: text,
            isPrimary: true,
            createdAt: now,
          ),
      ],
    );

    test('con su texto, todo se puede', () {
      final actions = InboxActions.of(item(text: 'Roma.'), PendingText.ready);

      expect(
        (actions.triage, actions.extract, actions.link, actions.review),
        (true, true, true, true),
      );
      expect(actions.passUnchanged, isTrue);
    });

    test('mientras no llega, nada de lo que necesita el texto', () {
      for (final text in [
        PendingText.arriving,
        PendingText.failed,
        PendingText.missing,
      ]) {
        final actions = InboxActions.of(item(), text);

        expect(
          (actions.triage, actions.extract, actions.link, actions.review),
          (false, false, false, false),
          reason: text.name,
        );
        expect(actions.passUnchanged, isFalse, reason: text.name);
      }
    });

    test('con el texto solo en su «Contenido» —o el propio en blanco— se '
        'tría, pero no se extrae ni se pasa entero: las dos trabajan sobre el '
        'del elemento', () {
      for (final own in [null, ' \n ']) {
        final actions = InboxActions.of(item(text: own), PendingText.ready);

        expect(
          (actions.triage, actions.extract, actions.link, actions.review),
          (true, false, true, true),
          reason: '$own',
        );
        expect(actions.passUnchanged, isFalse, reason: '$own');
      }
    });

    test('sin nada a la vista, ninguna', () {
      const none = InboxActions.none;

      expect(
        (none.triage, none.extract, none.link, none.review),
        (false, false, false, false),
      );
      expect(none.passUnchanged, isFalse);
    });
  });
}
