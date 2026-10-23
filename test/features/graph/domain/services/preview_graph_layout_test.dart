import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/graph/domain/services/preview_graph_layout.dart';

void main() {
  const widths = [280.0, 300.0, 340.0, 412.0, 800.0];

  PreviewLayout layoutOf(int count, double width) {
    final sizes = previewNodeSizes(width);
    return layoutLocalPreview(
      count: count,
      width: width,
      nodeSize: sizes.node,
      centerSize: sizes.center,
    );
  }

  group('layoutLocalPreview', () {
    test('ningún par de nodos se encima ni se toca, con cualquier cantidad y '
        'cualquier ancho', () {
      for (final width in widths) {
        for (var count = 0; count <= kLocalGraphPreviewMaxNeighbors; count++) {
          final layout = layoutOf(count, width);
          final all = [layout.center, ...layout.neighbors];
          for (var i = 0; i < all.length; i++) {
            for (var j = i + 1; j < all.length; j++) {
              expect(
                all[i].inflate(5).overlaps(all[j].inflate(5)),
                isFalse,
                reason: 'ancho $width, $count vecinos: nodos $i y $j',
              );
            }
          }
        }
      }
    });

    test('todos los nodos quedan dentro del lienzo', () {
      for (final width in widths) {
        for (var count = 0; count <= kLocalGraphPreviewMaxNeighbors; count++) {
          final layout = layoutOf(count, width);
          final canvas = Offset.zero & layout.size;
          expect(layout.size.width, width);
          for (final rect in [layout.center, ...layout.neighbors]) {
            expect(
              canvas.contains(rect.topLeft) &&
                  canvas.contains(rect.bottomRight),
              isTrue,
              reason: 'ancho $width, $count vecinos: $rect fuera de $canvas',
            );
          }
        }
      }
    });

    test('el elemento queda en el medio del lienzo', () {
      for (final width in widths) {
        for (var count = 0; count <= kLocalGraphPreviewMaxNeighbors; count++) {
          final layout = layoutOf(count, width);
          // Con un solo vecino el par entero se centra, no el elemento.
          if (count != 1) {
            expect(layout.center.center.dx, closeTo(width / 2, 0.001));
          }
          expect(layout.center.center.dy, closeTo(layout.size.height / 2, 1));
        }
      }
    });

    test('devuelve un rectángulo por vecino, en el orden pedido', () {
      for (var count = 0; count <= kLocalGraphPreviewMaxNeighbors; count++) {
        expect(layoutOf(count, 340).neighbors, hasLength(count));
      }
    });

    test('con varios vecinos usa todo el ancho de la tarjeta', () {
      for (final width in [300.0, 340.0, 412.0, 800.0]) {
        for (var count = 2; count <= kLocalGraphPreviewMaxNeighbors; count++) {
          final layout = layoutOf(count, width);
          final left = layout.neighbors.map((r) => r.left).reduce(_min);
          final right = layout.neighbors.map((r) => r.right).reduce(_max);
          // Pegados a los bordes (con su margen), no apretados en el medio.
          expect(left, lessThanOrEqualTo(10), reason: '$count a $width');
          expect(right, greaterThanOrEqualTo(width - 10));
        }
      }
    });

    test('ningún vínculo pasa por detrás de otro vecino', () {
      for (final width in widths) {
        for (var count = 0; count <= kLocalGraphPreviewMaxNeighbors; count++) {
          final layout = layoutOf(count, width);
          for (var i = 0; i < count; i++) {
            for (var j = 0; j < count; j++) {
              if (i == j) continue;
              expect(
                segmentHitsRect(
                  layout.center.center,
                  layout.neighbors[i].center,
                  layout.neighbors[j],
                ),
                isFalse,
                reason: 'ancho $width, $count vecinos: vínculo $i tapa a $j',
              );
            }
          }
        }
      }
    });

    test('con el tope de vecinos sigue siendo una vista previa chica', () {
      for (final width in [300.0, 340.0, 412.0]) {
        final layout = layoutOf(kLocalGraphPreviewMaxNeighbors, width);
        expect(layout.size.height, lessThan(260));
      }
    });

    test('con pocos vecinos el lienzo no se aplasta', () {
      for (var count = 0; count <= 3; count++) {
        expect(layoutOf(count, 340).size.height, greaterThanOrEqualTo(124));
      }
    });

    test('con un solo vecino, el par queda junto y centrado', () {
      final layout = layoutOf(1, 340);
      final pair = layout.center.expandToInclude(layout.neighbors.single);

      expect(pair.center.dx, closeTo(170, 0.001));
      expect(layout.neighbors.single.left, greaterThan(layout.center.right));
    });

    test('el más importante queda arriba y el resto sigue las agujas del '
        'reloj', () {
      for (var count = 3; count <= kLocalGraphPreviewMaxNeighbors; count++) {
        final layout = layoutOf(count, 340);
        final middle = layout.center.center;
        final columns = previewColumns(count);
        // Con cuatro no hay columna del medio: van en las esquinas.
        if (columns.middle == 0) continue;

        // El primero, arriba y en el medio.
        expect(layout.neighbors.first.center.dx, closeTo(middle.dx, 0.001));
        expect(layout.neighbors.first.center.dy, lessThan(middle.dy));
        // Después, los de la derecha, de arriba abajo.
        final right = layout.neighbors.sublist(1, 1 + columns.right);
        expect(right.every((r) => r.center.dx > middle.dx), isTrue);
        for (var i = 1; i < right.length; i++) {
          expect(right[i].center.dy, greaterThan(right[i - 1].center.dy));
        }
        // Y al final, los de la izquierda, de abajo arriba.
        final left = layout.neighbors.sublist(
          layout.neighbors.length - columns.left,
        );
        expect(left.every((r) => r.center.dx < middle.dx), isTrue);
        for (var i = 1; i < left.length; i++) {
          expect(left[i].center.dy, lessThan(left[i - 1].center.dy));
        }
      }
    });

    test('con cuatro vecinos van en las cuatro esquinas', () {
      final layout = layoutOf(4, 340);
      final middle = layout.center.center;

      expect(
        layout.neighbors
            .map((r) => (r.center.dx > middle.dx, r.center.dy > middle.dy))
            .toSet(),
        {(true, false), (true, true), (false, true), (false, false)},
      );
    });

    test('es determinista: los mismos datos dan la misma disposición', () {
      for (var count = 0; count <= kLocalGraphPreviewMaxNeighbors; count++) {
        final a = layoutOf(count, 340);
        final b = layoutOf(count, 340);
        expect(a.size, b.size);
        expect(a.center, b.center);
        expect(a.neighbors, b.neighbors);
      }
    });

    test('en un lienzo demasiado angosto cae a la grilla y no encima nada', () {
      const width = 120.0;
      const node = Size(76, 38);
      const center = Size(87, 46);
      for (var count = 1; count <= kLocalGraphPreviewMaxNeighbors; count++) {
        final layout = layoutLocalPreview(
          count: count,
          width: width,
          nodeSize: node,
          centerSize: center,
        );
        final all = [layout.center, ...layout.neighbors];
        expect(layout.neighbors, hasLength(count));
        for (var i = 0; i < all.length; i++) {
          expect(all[i].left, greaterThanOrEqualTo(0));
          expect(all[i].right, lessThanOrEqualTo(width));
          expect(all[i].bottom, lessThanOrEqualTo(layout.size.height));
          for (var j = i + 1; j < all.length; j++) {
            expect(all[i].overlaps(all[j]), isFalse, reason: '$count: $i/$j');
          }
        }
      }
    });
  });

  group('previewNodeSizes', () {
    test('caben tres a lo ancho con aire: vecino, elemento y vecino', () {
      for (final width in widths.where((w) => w >= 300)) {
        final sizes = previewNodeSizes(width);
        final row = 2 * sizes.node.width + sizes.center.width + 2 * 10;
        expect(row, lessThanOrEqualTo(width - 16), reason: 'ancho $width');
      }
    });

    test('un nodo nunca es más ancho de lo que se lee bien', () {
      expect(previewNodeSizes(2000).node.width, lessThanOrEqualTo(124));
      expect(previewNodeSizes(300).node.width, greaterThanOrEqualTo(76));
    });

    test('en un ancho minúsculo no se pasa del lienzo', () {
      final sizes = previewNodeSizes(60);

      expect(sizes.node.width, lessThanOrEqualTo(60));
      expect(sizes.center.width, lessThanOrEqualTo(60));
    });
  });

  group('previewColumns', () {
    test('reparte todos los vecinos, ni uno más ni uno menos', () {
      for (var count = 0; count <= 12; count++) {
        final columns = previewColumns(count);
        expect(columns.middle + columns.left + columns.right, count);
        expect(columns.middle, lessThanOrEqualTo(2));
      }
    });

    test('un vecino va a la derecha y dos, uno a cada lado', () {
      expect(previewColumns(1), (middle: 0, left: 0, right: 1));
      expect(previewColumns(2), (middle: 0, left: 1, right: 1));
    });

    test('con tres, uno arriba y uno a cada lado', () {
      expect(previewColumns(3), (middle: 1, left: 1, right: 1));
    });
  });

  group('segmentHitsRect', () {
    const rect = Rect.fromLTRB(10, 10, 20, 20);

    test('un segmento que cruza el rectángulo lo toca', () {
      expect(
        segmentHitsRect(const Offset(0, 15), const Offset(30, 15), rect),
        isTrue,
      );
    });

    test('uno que pasa de largo no lo toca', () {
      expect(
        segmentHitsRect(const Offset(0, 5), const Offset(30, 5), rect),
        isFalse,
      );
    });

    test('uno que se queda corto antes de llegar no lo toca', () {
      expect(
        segmentHitsRect(const Offset(0, 15), const Offset(8, 15), rect),
        isFalse,
      );
    });

    test('uno que termina adentro lo toca', () {
      expect(segmentHitsRect(Offset.zero, const Offset(15, 15), rect), isTrue);
    });
  });

  group('pickPreviewNeighbors', () {
    List<String> ids(int n) => [for (var i = 0; i < n; i++) 'n$i'];
    List<(String, String)> linksFromSeed(List<String> neighbors) => [
      for (final id in neighbors) ('seed', id),
    ];

    test('con pocos vecinos entran todos y no falta ninguno', () {
      final neighbors = ids(4);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: linksFromSeed(neighbors),
      );

      expect(picked.shown, neighbors);
      expect(picked.hidden, 0);
    });

    test('con muchos, entran el tope y el resto se cuenta en hidden', () {
      final neighbors = ids(25);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: linksFromSeed(neighbors),
      );

      expect(picked.shown, hasLength(kLocalGraphPreviewMaxNeighbors));
      expect(picked.hidden, 15);
      // A igualdad de fuerza, los más recientes (los primeros de la lista).
      expect(picked.shown, neighbors.take(10).toList());
    });

    test('lo que el repositorio ya dejó afuera se suma a hidden', () {
      final neighbors = ids(12);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: linksFromSeed(neighbors),
        omitted: 7,
      );

      expect(picked.shown, hasLength(10));
      expect(picked.hidden, 2 + 7);
    });

    test('el tope se puede cambiar', () {
      final neighbors = ids(6);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: linksFromSeed(neighbors),
        max: 3,
      );

      expect(picked.shown, hasLength(3));
      expect(picked.hidden, 3);
    });

    test('un vecino con más vínculos al elemento entra aunque sea viejo', () {
      final neighbors = ids(15);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: [
          ...linksFromSeed(neighbors),
          // El último de la lista (el más viejo) tiene un segundo vínculo, en
          // el otro sentido.
          ('n14', 'seed'),
        ],
      );

      expect(picked.shown.first, 'n14');
      expect(picked.shown, hasLength(10));
    });

    test('a igual cantidad de vínculos al elemento, gana el que más se vincula '
        'con los otros vecinos', () {
      final neighbors = ids(15);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: [...linksFromSeed(neighbors), ('n13', 'n14'), ('n12', 'n13')],
      );

      expect(picked.shown.take(2), ['n13', 'n12']);
      expect(picked.shown, contains('n14'));
    });

    test('un vínculo de un vecino consigo mismo no pesa', () {
      final neighbors = ids(12);

      final picked = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: [...linksFromSeed(neighbors), ('n11', 'n11'), ('seed', 'seed')],
      );

      expect(picked.shown, neighbors.take(10).toList());
    });

    test('es determinista', () {
      final neighbors = ids(25);
      final edges = [...linksFromSeed(neighbors), ('n20', 'n21')];

      final a = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: edges,
      );
      final b = pickPreviewNeighbors(
        seedId: 'seed',
        neighborIds: neighbors,
        edges: edges,
      );

      expect(a.shown, b.shown);
      expect(a.hidden, b.hidden);
    });
  });
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
