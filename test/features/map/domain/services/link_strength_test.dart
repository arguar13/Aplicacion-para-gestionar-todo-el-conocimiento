import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/services/link_graph_builder.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';

/// Cuánto pesa un vínculo y cómo se corta en los más y los menos fuertes
/// (F39, paso 8).
void main() {
  var minute = 0;
  LinkRow link(
    String from,
    String to, {
    RelationKind kind = RelationKind.relatedTo,
    ContentOrigin origin = ContentOrigin.user,
    double? confidence,
    DateTime? reviewedAt,
    bool anchored = false,
    int? at,
  }) => LinkRow(
    fromId: from,
    toId: to,
    kind: kind,
    createdAt: DateTime(2026, 10).add(Duration(minutes: at ?? minute++)),
    origin: origin,
    confidence: confidence,
    reviewedAt: reviewedAt,
    anchored: anchored,
  );

  setUp(() => minute = 0);

  group('linkStrength', () {
    test('un vínculo común de la persona pesa 2: el tipo suelto más su '
        'respaldo', () {
      expect(linkStrength(link('a', 'b')), 2);
    });

    test('el tipo pesa: sin precisar 1, con algo que decir 2, una '
        'contradicción 3', () {
      double weigh(RelationKind kind) =>
          linkStrength(link('a', 'b', kind: kind));

      expect(weigh(RelationKind.relatedTo), 2);
      for (final kind in [
        RelationKind.continues,
        RelationKind.cites,
        RelationKind.summarizes,
        RelationKind.extractedFrom,
        RelationKind.indexes,
      ]) {
        expect(weigh(kind), 3, reason: kind.name);
      }
      expect(weigh(RelationKind.contradicts), 4);
    });

    test('lo que la IA dejó sola pesa su confianza a la mitad; sin dato, '
        'nada', () {
      double ai(double? confidence) => linkStrength(
        link('a', 'b', origin: ContentOrigin.ai, confidence: confidence),
      );

      expect(ai(1), 1.5);
      expect(ai(0.5), 1.25);
      expect(ai(null), 1);
      // Una confianza fuera de 0 a 1 no desborda.
      expect(ai(7), 1.5);
      expect(ai(-3), 1);
    });

    test('lo de la IA que la persona revisó pesa como lo de la persona', () {
      final reviewed = link(
        'a',
        'b',
        origin: ContentOrigin.ai,
        confidence: 0.1,
        reviewedAt: DateTime(2026, 10, 2),
      );

      expect(linkStrength(reviewed), 2);
    });

    test('saber de qué fragmento sale suma 0,5', () {
      expect(linkStrength(link('a', 'b', anchored: true)), 2.5);
    });

    test('cada vínculo de más entre los mismos dos elementos suma 1', () {
      expect(linkStrength(link('a', 'b')), 2);
      expect(linkStrength(link('a', 'b'), pairLinks: 3), 4);
      // Un conteo en cero o negativo no resta.
      expect(linkStrength(link('a', 'b'), pairLinks: 0), 2);
    });

    test(
      'no mira la fecha: el mismo vínculo, hoy o hace un año, pesa igual',
      () {
        expect(
          linkStrength(link('a', 'b', at: 0)),
          linkStrength(link('a', 'b', at: 600000)),
        );
      },
    );
  });

  group('cutLinksByStrength', () {
    // Cuatro vínculos, de más a menos: contradice (4), cita (3), cita de la IA
    // (2,5), relacionado de la IA (1,x).
    List<LinkRow> four() => [
      link('c', 'd', kind: RelationKind.cites, at: 1),
      link('g', 'h', origin: ContentOrigin.ai, confidence: 0.6, at: 2),
      link('a', 'b', kind: RelationKind.contradicts, at: 3),
      link(
        'e',
        'f',
        kind: RelationKind.cites,
        origin: ContentOrigin.ai,
        confidence: 1,
        at: 4,
      ),
    ];

    String name(LinkRow row) => '${row.fromId}${row.toId}';

    test('todos devuelve las mismas filas, sin tocar nada', () {
      final rows = four();

      expect(cutLinksByStrength(rows, LinkStrengthFilter.all), same(rows));
    });

    test('los más fuertes son la mitad de arriba, de más a menos', () {
      final cut = cutLinksByStrength(four(), LinkStrengthFilter.strongest);

      expect(cut.map(name), ['ab', 'cd']);
    });

    test('los menos fuertes son la mitad de abajo, y entre las dos están '
        'todos', () {
      final weakest = cutLinksByStrength(four(), LinkStrengthFilter.weakest);
      final strongest = cutLinksByStrength(
        four(),
        LinkStrengthFilter.strongest,
      );

      expect(weakest.map(name), ['ef', 'gh']);
      expect({...weakest, ...strongest}, hasLength(4));
    });

    test('con un número impar, el del medio está en las dos mitades', () {
      final rows = [
        link('a', 'b', kind: RelationKind.contradicts),
        link('c', 'd', kind: RelationKind.cites),
        link('e', 'f'),
      ];

      expect(cutLinksByStrength(rows, LinkStrengthFilter.strongest).map(name), [
        'ab',
        'cd',
      ]);
      expect(cutLinksByStrength(rows, LinkStrengthFilter.weakest).map(name), [
        'cd',
        'ef',
      ]);
    });

    test('con un solo vínculo, ninguna mitad queda vacía', () {
      final rows = [link('a', 'b')];

      expect(cutLinksByStrength(rows, LinkStrengthFilter.strongest), rows);
      expect(cutLinksByStrength(rows, LinkStrengthFilter.weakest), rows);
    });

    test('sin vínculos, nada', () {
      for (final filter in LinkStrengthFilter.values) {
        expect(cutLinksByStrength(const [], filter), isEmpty);
      }
    });

    test('los empates van del más reciente al más viejo, y no dependen del '
        'orden en que llegaron las filas', () {
      // Cuatro vínculos del mismo peso: manda la fecha.
      final rows = [
        link('a', 'b', at: 10),
        link('c', 'd', at: 40),
        link('e', 'f', at: 20),
        link('g', 'h', at: 30),
      ];

      final forward = cutLinksByStrength(rows, LinkStrengthFilter.strongest);
      final backward = cutLinksByStrength(
        rows.reversed.toList(),
        LinkStrengthFilter.strongest,
      );

      expect(forward.map(name), ['cd', 'gh']);
      expect(backward.map(name), ['cd', 'gh']);
      expect(cutLinksByStrength(rows, LinkStrengthFilter.weakest).map(name), [
        'ef',
        'ab',
      ]);
    });

    test('si empatan hasta en la fecha, desempatan los identificadores y el '
        'tipo', () {
      final rows = [
        link('b', 'x', at: 5),
        link('a', 'z', at: 5),
        link('a', 'y', kind: RelationKind.cites, at: 5),
        link('a', 'y', kind: RelationKind.continues, at: 5),
      ];

      final strongest = cutLinksByStrength(
        rows.reversed.toList(),
        LinkStrengthFilter.strongest,
      );
      final weakest = cutLinksByStrength(
        rows.reversed.toList(),
        LinkStrengthFilter.weakest,
      );

      // a-y tiene dos vínculos entre los mismos, y los dos pesan igual.
      expect(strongest.map((r) => '${name(r)}:${r.kind.name}'), [
        'ay:cites',
        'ay:continues',
      ]);
      expect(weakest.map(name), ['az', 'bx']);
    });

    test('con el mismo origen y la misma fecha, desempata el destino', () {
      final rows = [
        link('a', 'z', at: 5),
        link('a', 'y', at: 5),
        link('a', 'x', at: 5),
        link('a', 'w', at: 5),
      ];

      expect(cutLinksByStrength(rows, LinkStrengthFilter.strongest).map(name), [
        'aw',
        'ax',
      ]);
      expect(cutLinksByStrength(rows, LinkStrengthFilter.weakest).map(name), [
        'ay',
        'az',
      ]);
    });

    test('los vínculos repetidos entre los mismos dos elementos pesan más, '
        'también si van en sentidos opuestos', () {
      final rows = [
        link('a', 'b'),
        link('b', 'a', kind: RelationKind.cites),
        link('c', 'd'),
        link('e', 'f'),
      ];

      final strongest = cutLinksByStrength(rows, LinkStrengthFilter.strongest);

      // a-b y b-a: 2 y 3, más 1 cada uno por ser dos. c-d y e-f, solos: 2.
      expect(strongest.map(name), ['ba', 'ab']);
    });

    test('un vínculo de un elemento consigo mismo no cuenta', () {
      final rows = [link('a', 'a'), link('b', 'c')];

      expect(cutLinksByStrength(rows, LinkStrengthFilter.strongest).map(name), [
        'bc',
      ]);
      expect(cutLinksByStrength(rows, LinkStrengthFilter.weakest).map(name), [
        'bc',
      ]);
    });
  });
}
