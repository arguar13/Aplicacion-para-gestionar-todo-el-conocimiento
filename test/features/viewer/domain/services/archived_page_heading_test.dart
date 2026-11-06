import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_heading.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';

/// Abrir una página web archivada en un título (F46, paso 4: «Abrir en el
/// original» desde un capítulo del Índice): cuál se marca, y que la página
/// lleve solo el programa chico de la app.
void main() {
  const page = '''
<html><head><title>Roma</title></head><body>
<nav><h2>Menú</h2></nav>
<h1>Historia de Roma</h1>
<p>Intro.</p>
<h2 id="hist">La Monarquía <span class="edit">[editar]</span></h2>
<p>Siete reyes.</p>
<h2>Referencias</h2>
<p>Libros.</p>
<h3>LA REPÚBLICA</h3>
<div role="heading">Notas al pie</div>
<h2>Referencias</h2>
<script>alert("de la página")</script>
<a href="#" onclick="robar()">enlace</a>
</body></html>''';

  String? marked(ArchivedHeading heading) {
    final document = html_parser.parse(page);
    if (!markArchivedHeading(document, heading)) return null;
    final found = document.querySelectorAll('#$archivedHeadingId');
    expect(found, hasLength(1), reason: 'un solo título marcado');
    return found.single.text.trim();
  }

  group('qué título se marca', () {
    test('el que dice lo mismo, sin mayúsculas, acentos ni puntuación', () {
      expect(marked((title: 'La República', occurrence: 0)), 'LA REPÚBLICA');
      expect(
        marked((title: 'historia de roma', occurrence: 0)),
        'Historia de Roma',
      );
    });

    test('entre los iguales, el de su lugar; si la página tiene menos, el '
        'primero', () {
      final document = html_parser.parse(page);
      expect(
        markArchivedHeading(document, (title: 'Referencias', occurrence: 1)),
        isTrue,
      );
      final all = document.querySelectorAll('h2');
      expect(all.last.id, archivedHeadingId);
      expect(all[2].id, isEmpty);

      final fewer = html_parser.parse(page);
      markArchivedHeading(fewer, (title: 'Referencias', occurrence: 7));
      expect(fewer.querySelectorAll('h2')[2].id, archivedHeadingId);
    });

    test('lo que la página le agrega al título —«[editar]»— no lo esconde, y '
        'el «id» que traía se reemplaza', () {
      final document = html_parser.parse(page);
      expect(
        markArchivedHeading(document, (title: 'La Monarquía', occurrence: 0)),
        isTrue,
      );
      expect(document.querySelector('#hist'), isNull);
      expect(
        document.querySelector('#$archivedHeadingId')!.text,
        contains('La Monarquía'),
      );
    });

    test('también un encabezado por su papel, sin etiqueta de título', () {
      expect(marked((title: 'Notas al pie', occurrence: 0)), 'Notas al pie');
    });

    test('un título que la página no tiene, o vacío, no marca nada', () {
      expect(marked((title: 'Cartago', occurrence: 0)), isNull);
      expect(marked((title: ' ¿? ', occurrence: 0)), isNull);
      expect(marked((title: 'Historia', occurrence: 0)), isNull);
    });
  });

  group('la página que se muestra', () {
    test('con el título, lleva el programa que va a él y sin los de la '
        'página', () {
      final shown = showArchivedPage(
        page,
        heading: (title: 'La República', occurrence: 0),
        headingFlash: 0xFFFFE08A,
      );
      expect(shown.scripted, isTrue);
      expect(shown.alignment, isNull);
      final document = html_parser.parse(shown.html);
      expect(
        document.querySelector('#$archivedHeadingId')!.text,
        'LA REPÚBLICA',
      );
      final scripts = document.querySelectorAll('script');
      expect(scripts.map((s) => s.id), ['sinapsis-heading-script']);
      expect(shown.html, isNot(contains('alert(')));
      expect(shown.html, isNot(contains('robar()')));
      expect(
        document.querySelector('#sinapsis-heading')!.text,
        contains('#ffe08a'),
      );
      expect(scripts.single.text, contains('"smooth":true'));
    });

    test('«sin animaciones»: salta, y el resalte no se desvanece', () {
      final shown = showArchivedPage(
        page,
        heading: (title: 'La República', occurrence: 0),
        still: true,
      );
      final document = html_parser.parse(shown.html);
      expect(
        document.querySelector('#sinapsis-heading-script')!.text,
        contains('"smooth":false'),
      );
      expect(
        document.querySelector('#sinapsis-heading')!.text,
        isNot(contains('transition')),
      );
    });

    test('con un título que no está, la página de siempre, sin programa', () {
      final shown = showArchivedPage(
        page,
        heading: (title: 'Cartago', occurrence: 0),
      );
      expect(shown.scripted, isFalse);
      expect(shown.html, isNot(contains('sinapsis-heading')));
      expect(shown.html, contains('alert('));
      expect(showArchivedPage(page).scripted, isFalse);
    });

    test('el título se marca después de contar el texto: lo estudiado se '
        'ubica igual que sin él', () {
      const content =
          'Historia de Roma\n\nIntro.\n\nLa Monarquía\n\nSiete reyes.';
      const colors = (summary: 1, synthesis: 2, keyword: 3, summaryLine: 4);
      final plain = showArchivedPage(
        page,
        study: (content: content, colors: colors),
      );
      final heading = showArchivedPage(
        page,
        study: (content: content, colors: colors),
        heading: (title: 'La Monarquía', occurrence: 0),
      );
      expect(heading.scripted, isTrue);
      expect(
        heading.alignment!.pageRangesOf(0, content.length),
        plain.alignment!.pageRangesOf(0, content.length),
      );
      final scripts = html_parser
          .parse(heading.html)
          .querySelectorAll('script')
          .map((s) => s.id);
      expect(
        scripts,
        containsAll(['sinapsis-study-script', 'sinapsis-heading-script']),
      );
    });
  });

  group('la dirección del original', () {
    test('sin lugar, la de siempre, sin un «?» colgando', () {
      expect(RoutePaths.processedOriginal('d'), '/processed/d/original');
    });

    test('con una página o un título, y su lugar entre los iguales', () {
      expect(
        Uri.parse(RoutePaths.processedOriginal('d', page: 47)).queryParameters,
        {'page': '47'},
      );
      expect(
        Uri.parse(
          RoutePaths.processedOriginal(
            'd',
            heading: 'Roma & Cartago',
            occurrence: 2,
          ),
        ).queryParameters,
        {'heading': 'Roma & Cartago', 'nth': '2'},
      );
      expect(
        Uri.parse(
          RoutePaths.processedOriginal('d', heading: 'Roma'),
        ).queryParameters,
        {'heading': 'Roma'},
      );
    });
  });
}
