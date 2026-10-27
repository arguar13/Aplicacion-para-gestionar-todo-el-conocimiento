import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_documents.dart';

import '../../timeline_fixtures.dart';

/// Los documentos que tienen fechas (F40): lo que se elige en la hoja de
/// «Documento» de la línea de tiempo.
void main() {
  test('un documento con dos fechas es uno solo, con cuántas tiene', () {
    final documents = groupTimelineDocuments([
      eventAt('darwin', dateOf(1809), title: 'Darwin'),
      eventAt('darwin', dateOf(1859), title: 'Darwin'),
      eventAt('roma', dateOf(476), title: 'Roma'),
    ]);

    expect(documents.map((d) => d.itemId), ['darwin', 'roma']);
    expect(documents.first.eventCount, 2);
    expect(documents.last.eventCount, 1);
  });

  test('de cuándo a cuándo van sus fechas, sin importar en qué orden '
      'llegaron', () {
    final [darwin] = groupTimelineDocuments([
      eventAt('darwin', dateOf(1859), title: 'Darwin'),
      eventAt('darwin', dateOf(1809), title: 'Darwin'),
      eventAt('darwin', dateOf(1882), title: 'Darwin'),
    ]);

    expect(darwin.firstDate, '1809');
    expect(darwin.lastDate, '1882');
    expect(darwin.range, '1809 – 1882');
  });

  test('con una sola fecha, o todas iguales, el rango es esa fecha', () {
    final [uno] = groupTimelineDocuments([
      eventAt('a', dateOf(44, bce: true), title: 'César'),
    ]);
    final [mismo] = groupTimelineDocuments([
      eventAt('b', dateOf(476), title: 'Roma'),
      eventAt('b', dateOf(476), title: 'Roma'),
    ]);

    expect(uno.range, '44 a.C.');
    expect(mismo.range, '476');
  });

  test('se ordenan por título sin distinguir mayúsculas ni acentos', () {
    final documents = groupTimelineDocuments([
      eventAt('z', dateOf(1), title: 'zeta'),
      eventAt('e', dateOf(2), title: 'Éxodo'),
      eventAt('a', dateOf(3), title: 'Ábaco'),
      eventAt('b', dateOf(4), title: 'beta'),
    ]);

    expect(documents.map((d) => d.title), ['Ábaco', 'beta', 'Éxodo', 'zeta']);
  });

  test('conserva de qué es cada documento', () {
    final [nota, fuente] = groupTimelineDocuments([
      eventAt('n', dateOf(1), title: 'A nota'),
      eventAt(
        'f',
        dateOf(2),
        title: 'B fuente',
        sourceKind: SourceKind.webPage,
      ),
    ]);

    expect(nota.sourceKind, SourceKind.manualNote);
    expect(fuente.sourceKind, SourceKind.webPage);
  });

  test('sin hechos no hay documentos', () {
    expect(groupTimelineDocuments(const []), isEmpty);
  });

  test('diez mil hechos de mil documentos se agrupan de una vez', () {
    final events = [
      for (var i = 0; i < 10000; i++)
        eventAt(
          'doc${i % 1000}',
          dateOf(1 + i),
          title: 'Documento ${i % 1000}',
        ),
    ];

    final documents = groupTimelineDocuments(events);

    expect(documents, hasLength(1000));
    expect(documents.every((d) => d.eventCount == 10), isTrue);
  });

  group('hechos fechados dentro de un documento', () {
    TimelineEvent fact(
      String id,
      HistoricalDate date, {
      HistoricalDate? end,
      String document = 'Historia del siglo XX',
    }) => TimelineEvent(
      itemId: 'libro',
      title: 'Hecho $id',
      itemTitle: document,
      date: date,
      end: end,
      sourceKind: SourceKind.document,
      datedEventId: id,
    );

    test(
      'el documento se llama como el documento y no como su primer hecho',
      () {
        final [libro] = groupTimelineDocuments([
          fact('a', dateOf(1914)),
          fact('b', dateOf(1939)),
        ]);

        expect(libro.title, 'Historia del siglo XX');
        expect(libro.eventCount, 2);
      },
    );

    test('se ordenan por el título del documento, no por el del hecho', () {
      final documents = groupTimelineDocuments([
        TimelineEvent(
          itemId: 'z',
          title: 'Aaa un hecho',
          itemTitle: 'Zeta',
          date: dateOf(1),
          sourceKind: SourceKind.document,
          datedEventId: 'x',
        ),
        TimelineEvent(
          itemId: 'a',
          title: 'Zzz otro hecho',
          itemTitle: 'Alfa',
          date: dateOf(2),
          sourceKind: SourceKind.document,
          datedEventId: 'y',
        ),
      ]);

      expect(documents.map((d) => d.title), ['Alfa', 'Zeta']);
    });

    test('hasta cuándo llega es donde termina el último tramo', () {
      final [libro] = groupTimelineDocuments([
        fact('a', dateOf(1900)),
        fact('b', dateOf(1914), end: dateOf(1918)),
      ]);

      expect(libro.firstDate, '1900');
      expect(libro.lastDate, '1918');
      expect(libro.range, '1900 – 1918');
    });
  });
}
