import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';

/// Lo que el visor de páginas le pide al otro hilo (F46, paso 5c): el
/// archivo, no su texto —se lee allá—, y en la vista previa de una ficha,
/// solo el comienzo de la página.
void main() {
  const colors = (summary: 1, synthesis: 2, keyword: 3, summaryLine: 4);
  const text = (
    itemId: 'i',
    renditionId: 'r',
    content: 'Roma.',
    markdown: true,
  );

  test('a pantalla completa, la página entera, en su título', () {
    final job = archivedPageJobOf(
      const WebPageViewerView(
        path: '/paginas/roma.html',
        text: text,
        mobile: true,
        heading: (title: 'Historia', occurrence: 1),
      ),
      colors: colors,
      still: true,
    );

    expect(job.path, '/paginas/roma.html');
    expect(job.study, (content: 'Roma.', colors: colors));
    expect(job.mobile, isTrue);
    expect(job.heading, (title: 'Historia', occurrence: 1));
    expect(job.still, isTrue);
    expect(job.previewLetters, isNull);
  });

  test('en la ficha, solo el comienzo; sin texto, sin estudio', () {
    final job = archivedPageJobOf(
      const WebPageViewerView(path: '/paginas/roma.html', preview: true),
      colors: colors,
      still: false,
    );

    expect(job.previewLetters, archivedPagePreviewLetters);
    expect(job.study, isNull);
    expect(job.mobile, isFalse);
  });
}
