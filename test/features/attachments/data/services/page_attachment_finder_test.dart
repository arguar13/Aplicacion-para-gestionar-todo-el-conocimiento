import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/attachments/data/services/page_attachment_finder.dart';

void main() {
  List<(String, RenditionKind, String?)> find(String html) => [
    for (final c in findPageAttachments(html))
      (c.url.toString(), c.kind, c.title),
  ];

  test('las fotos, en su mejor versión y en orden', () {
    const html = '''
<p>Texto.</p>
<figure>
  <img src="https://up.org/thumb/250px-Coliseo.jpg"
       srcset="https://up.org/thumb/330px-Coliseo.jpg 1.5x, https://up.org/thumb/500px-Coliseo.jpg 2x"
       width="250" height="180" alt="">
  <figcaption>El Coliseo de noche</figcaption>
</figure>
<p><img src="https://up.org/a.jpg" data-srcset="https://up.org/a-320.jpg 320w, https://up.org/a-1280.jpg 1280w" alt="Una vista"></p>
<img class="lazyload" data-src="https://up.org/b.png">
<img src="https://up.org/mapa.svg" alt="Mapa">
''';

    expect(find(html), [
      (
        'https://up.org/thumb/500px-Coliseo.jpg',
        RenditionKind.image,
        'El Coliseo de noche',
      ),
      ('https://up.org/a-1280.jpg', RenditionKind.image, 'Una vista'),
      ('https://up.org/b.png', RenditionKind.image, null),
      ('https://up.org/mapa.svg', RenditionKind.image, 'Mapa'),
    ]);
  });

  test('ni íconos, ni píxeles, ni data:, ni repetidas', () {
    const html = '''
<img src="https://up.org/bandera.png" width="20" height="13" alt="Italia">
<img src="https://up.org/pixel.gif" width="1" height="1">
<img src="https://up.org/icono.png" width="16">
<img src="data:image/png;base64,AAAA" alt="incrustada">
<img src="https://up.org/deco.png" role="presentation">
<img src="https://up.org/foto.jpg#arriba" alt="Foto">
<img src="https://up.org/foto.jpg" alt="Otra vez">
''';

    expect(find(html), [
      ('https://up.org/foto.jpg', RenditionKind.image, 'Foto'),
    ]);
  });

  test('los archivos que enlaza el texto, con el texto del enlace', () {
    const html = '''
<p>Ver el <a href="https://x.org/docs/informe.pdf">informe anual</a>, el
<a href="https://x.org/libro.epub">libro</a>, la
<a href="https://x.org/charla.mp3">charla</a>, los
<a href="https://x.org/datos.zip">datos</a> y el
<a href="https://x.org/otra-nota">artículo relacionado</a>.</p>
<p><a href="https://es.wikipedia.org/wiki/Archivo:Coliseo.jpg"><img src="https://up.org/c.jpg" alt="Coliseo"></a></p>
<p><a href="mailto:a@b.c">escribir</a> <a href="#notas">notas</a></p>
''';

    expect(find(html), [
      ('https://x.org/docs/informe.pdf', RenditionKind.pdf, 'informe anual'),
      ('https://x.org/libro.epub', RenditionKind.document, 'libro'),
      ('https://x.org/charla.mp3', RenditionKind.audio, 'charla'),
      ('https://x.org/datos.zip', RenditionKind.file, 'datos'),
      // El enlace que solo envuelve la foto no cuenta: la foto, sí.
      ('https://up.org/c.jpg', RenditionKind.image, 'Coliseo'),
    ]);
  });

  test('los videos y audios incrustados', () {
    const html = '''
<video controls title="La entrevista" poster="https://x.org/p.jpg">
  <source src="https://x.org/entrevista.webm" type="video/webm">
  <source src="https://x.org/entrevista.mp4" type="video/mp4">
</video>
<figure><audio src="https://x.org/himno.ogg"></audio><figcaption>El himno</figcaption></figure>
<embed src="https://x.org/plano.pdf" type="application/pdf">
<object data="https://x.org/otra-pagina"></object>
''';

    expect(find(html), [
      ('https://x.org/entrevista.webm', RenditionKind.video, 'La entrevista'),
      ('https://x.org/himno.ogg', RenditionKind.audio, 'El himno'),
      ('https://x.org/plano.pdf', RenditionKind.pdf, null),
    ]);
  });

  test('la copia del Internet Archive de un mismo PDF no se repite', () {
    // Así cita Wikipedia: el original y "Archived".
    const html = '''
<a href="http://www.nps.gov/folleto.pdf">el folleto</a>
<a href="https://web.archive.org/web/20100215210613/http://www.nps.gov/folleto.pdf">Archived</a>
<a href="https://www.nps.gov/folleto.pdf">otra vez</a>
''';
    expect(find(html), [
      ('http://www.nps.gov/folleto.pdf', RenditionKind.pdf, 'el folleto'),
    ]);
  });

  test('las posiciones son el orden de la página', () {
    final found = findPageAttachments('''
<a href="https://x.org/b.pdf">b</a>
<img src="https://x.org/a.jpg" alt="a">
''');
    expect(found.map((c) => c.position), [0, 1]);
  });

  test('una galería enorme se corta en el máximo', () {
    final html = [
      for (var i = 0; i < 500; i++) '<img src="https://x.org/$i.jpg">',
    ].join();
    expect(findPageAttachments(html, maxCandidates: 120), hasLength(120));
    expect(findPageAttachments(html), hasLength(kMaxPageAttachments));
  });
}
