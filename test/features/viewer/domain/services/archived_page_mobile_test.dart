import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/viewer/domain/services/archived_page_mobile.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';

/// La página web de Procesado como en un navegador del teléfono (F45, paso
/// 4): el ancho de la pantalla, sin el menú lateral ni las columnas de
/// escritorio, y el texto de siempre para estudiar sobre ella.
void main() {
  // Lo que importa de una página de Wikipedia archivada: el ancho de
  // escritorio que declara, su menú, su índice, sus herramientas y el
  // artículo con su cuadro de datos.
  const wikipedia = '''
<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=1120">
<title>Roma</title>
</head><body>
<div class="vector-header-container"><nav>Menú principal</nav></div>
<div class="mw-page-container"><div class="vector-column-start">Contenidos</div>
<main id="content" class="mw-body"><div id="mw-content-text"><div class="mw-parser-output">
<table class="infobox"><tr><td>Fundación: 753 a. C.</td></tr></table>
<p>Roma es la capital de Italia.</p>
</div></div></main>
<div class="vector-column-end">Herramientas</div></div>
</body></html>''';

  const colors = (summary: 1, synthesis: 2, keyword: 3, summaryLine: 4);
  const content = 'Roma es la capital de Italia.';

  test('el ancho de la pantalla en lugar del de escritorio: un solo '
      '<meta name="viewport">', () {
    final document = html_parser.parse(wikipedia);
    makeArchivedPageMobile(document);

    final viewports = document.querySelectorAll('meta[name="viewport"]');
    expect(viewports, hasLength(1));
    expect(viewports.single.attributes['content'], kMobileViewport);
  });

  test('una sola columna: el menú, el índice y las herramientas se ocultan, '
      'y el cuadro de datos deja de flotar', () {
    final document = html_parser.parse(wikipedia);
    makeArchivedPageMobile(document);

    final style = document.head!.querySelector('#$kMobilePageStyleId')!;
    // Al final del encabezado: gana a lo de la página.
    expect(document.head!.children.last, same(style));
    final css = style.text;
    for (final hidden in [
      'nav',
      '.vector-header-container',
      '.vector-column-start',
      '.vector-column-end',
    ]) {
      final rule = RegExp(
        r'([^{}]*)\{display:none!important;\}',
      ).firstMatch(css)!.group(1)!.split(',').map((s) => s.trim());
      expect(rule, contains(hidden), reason: hidden);
    }
    expect(css, contains('.infobox'));
    expect(css, contains('float:none!important'));
    expect(css, contains('img,video'));
  });

  test('lo que se oculta sigue en la página: el cuerpo es el mismo, y se '
      'estudia y se resalta sobre el mismo texto', () {
    final desktop = showArchivedPage(
      wikipedia,
      study: (content: content, colors: colors),
    );
    final mobile = showArchivedPage(
      wikipedia,
      study: (content: content, colors: colors),
      mobile: true,
    );

    expect(
      html_parser.parse(mobile.html).body!.outerHtml,
      html_parser.parse(desktop.html).body!.outerHtml,
    );
    final start = content.indexOf('capital');
    final desktopRanges = desktop.alignment!.pageRangesOf(start, start + 7);
    final mobileRanges = mobile.alignment!.pageRangesOf(start, start + 7);
    expect(mobileRanges, desktopRanges);
    expect(mobileRanges, isNotEmpty);
  });

  test('pedida al mostrar la página, con texto para estudiar o sin él, la '
      'copia lleva el ancho del teléfono y la hoja de la vista móvil', () {
    for (final shown in [
      showArchivedPage(wikipedia, mobile: true).html,
      showArchivedPage(
        wikipedia,
        study: (content: content, colors: colors),
        mobile: true,
      ).html,
    ]) {
      final document = html_parser.parse(shown);
      expect(
        document
            .querySelectorAll('meta[name="viewport"]')
            .map((meta) => meta.attributes['content']),
        [kMobileViewport],
      );
      expect(document.querySelector('#$kMobilePageStyleId'), isNotNull);
    }
  });

  test('sin pedirlo, la página se ve como era', () {
    final shown = showArchivedPage(wikipedia).html;
    expect(shown, contains('width=1120'));
    expect(shown, isNot(contains(kMobilePageStyleId)));
  });

  test('una página sin encabezado lo recibe; dos veces no suma dos', () {
    final document = html_parser.parse('<p>Hola</p>');
    makeArchivedPageMobile(document);
    makeArchivedPageMobile(document);

    expect(document.querySelectorAll('meta[name="viewport"]'), hasLength(1));
    expect(document.querySelectorAll('#$kMobilePageStyleId'), hasLength(1));
  });
}
