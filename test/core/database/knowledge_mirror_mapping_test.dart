import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';

void main() {
  group('itemKindFor', () {
    test('una nota manual es ItemKind.note', () {
      expect(itemKindFor(SourceKind.manualNote), ItemKind.note);
    });

    test('cualquier otro tipo de fuente es ItemKind.source', () {
      for (final kind in SourceKind.values.where(
        (k) => k != SourceKind.manualNote,
      )) {
        expect(itemKindFor(kind), ItemKind.source, reason: kind.name);
      }
    });
  });

  group('initialItemStateFor', () {
    test('ready es processed', () {
      expect(initialItemStateFor(ProcessingState.ready), ItemState.processed);
    });

    test('pending, processing y failed son captured', () {
      for (final state in [
        ProcessingState.pending,
        ProcessingState.processing,
        ProcessingState.failed,
      ]) {
        expect(
          initialItemStateFor(state),
          ItemState.captured,
          reason: state.name,
        );
      }
    });
  });

  group('sourceProcessingStatusFor', () {
    test('mapea cada ProcessingState uno a uno', () {
      expect(
        sourceProcessingStatusFor(ProcessingState.pending),
        SourceProcessingStatus.pending,
      );
      expect(
        sourceProcessingStatusFor(ProcessingState.processing),
        SourceProcessingStatus.running,
      );
      expect(
        sourceProcessingStatusFor(ProcessingState.ready),
        SourceProcessingStatus.done,
      );
      expect(
        sourceProcessingStatusFor(ProcessingState.failed),
        SourceProcessingStatus.failed,
      );
    });
  });

  group('nextMirrorState', () {
    test('sin fila previa, usa el estado inicial', () {
      expect(
        nextMirrorState(current: null, processingState: ProcessingState.ready),
        ItemState.processed,
      );
      expect(
        nextMirrorState(
          current: null,
          processingState: ProcessingState.pending,
        ),
        ItemState.captured,
      );
    });

    test('una referencia sin fila previa nace triada, esté como esté', () {
      for (final state in ProcessingState.values) {
        expect(
          nextMirrorState(
            current: null,
            processingState: state,
            sourceKind: SourceKind.reference,
          ),
          ItemState.triaged,
          reason: state.name,
        );
      }
    });

    test('cualquier otra fuente sigue el camino de siempre', () {
      for (final kind in SourceKind.values.where(
        (k) => k != SourceKind.reference,
      )) {
        expect(
          nextMirrorState(
            current: null,
            processingState: ProcessingState.ready,
            sourceKind: kind,
          ),
          ItemState.processed,
          reason: kind.name,
        );
      }
    });

    test('una referencia con fila previa conserva su estado', () {
      expect(
        nextMirrorState(
          current: ItemState.distilled,
          processingState: ProcessingState.ready,
          sourceKind: SourceKind.reference,
        ),
        ItemState.distilled,
      );
    });

    test('una referencia que recibe su archivo entra a la Bandeja, como '
        'recién guardada (F41, decisión E)', () {
      for (final (processing, expected) in [
        (ProcessingState.pending, ItemState.captured),
        (ProcessingState.processing, ItemState.captured),
        (ProcessingState.ready, ItemState.processed),
      ]) {
        expect(
          nextMirrorState(
            current: ItemState.triaged,
            processingState: processing,
            sourceKind: SourceKind.document,
            previousSourceKind: SourceKind.reference,
          ),
          expected,
          reason: processing.name,
        );
      }
    });

    test('solo desde triada, que en una referencia es como nació: no pisa '
        'una decisión, ni mueve lo que ya era un documento o sigue siendo '
        'una referencia', () {
      for (final current in [ItemState.distilled, ItemState.discarded]) {
        expect(
          nextMirrorState(
            current: current,
            processingState: ProcessingState.pending,
            sourceKind: SourceKind.document,
            previousSourceKind: SourceKind.reference,
          ),
          current,
          reason: current.name,
        );
      }
      expect(
        nextMirrorState(
          current: ItemState.triaged,
          processingState: ProcessingState.pending,
          sourceKind: SourceKind.document,
          previousSourceKind: SourceKind.document,
        ),
        ItemState.triaged,
      );
      expect(
        nextMirrorState(
          current: ItemState.triaged,
          processingState: ProcessingState.ready,
          sourceKind: SourceKind.reference,
          previousSourceKind: SourceKind.reference,
        ),
        ItemState.triaged,
      );
      expect(
        nextMirrorState(
          current: ItemState.triaged,
          processingState: ProcessingState.pending,
          previousSourceKind: SourceKind.reference,
        ),
        ItemState.triaged,
      );
    });

    test('captured + ready avanza a processed', () {
      expect(
        nextMirrorState(
          current: ItemState.captured,
          processingState: ProcessingState.ready,
        ),
        ItemState.processed,
      );
    });

    test('captured + pending/processing/failed no cambia', () {
      for (final state in [
        ProcessingState.pending,
        ProcessingState.processing,
        ProcessingState.failed,
      ]) {
        expect(
          nextMirrorState(current: ItemState.captured, processingState: state),
          ItemState.captured,
          reason: state.name,
        );
      }
    });

    test('processed + ready no cambia (ya estaba)', () {
      expect(
        nextMirrorState(
          current: ItemState.processed,
          processingState: ProcessingState.ready,
        ),
        ItemState.processed,
      );
    });

    test('triaged + ready NO retrocede a processed', () {
      expect(
        nextMirrorState(
          current: ItemState.triaged,
          processingState: ProcessingState.ready,
        ),
        ItemState.triaged,
      );
    });

    test('distilled + ready NO retrocede', () {
      expect(
        nextMirrorState(
          current: ItemState.distilled,
          processingState: ProcessingState.ready,
        ),
        ItemState.distilled,
      );
    });

    test('discarded + ready NO revive el elemento', () {
      expect(
        nextMirrorState(
          current: ItemState.discarded,
          processingState: ProcessingState.ready,
        ),
        ItemState.discarded,
      );
    });
  });
}
