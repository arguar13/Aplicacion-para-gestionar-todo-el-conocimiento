import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_html_text.dart';

String text(String html, {bool markdown = true}) =>
    ankiHtmlToText(html, markdown: markdown).text;

void main() {
  group('saltos de línea', () {
    test('<br> en sus tres formas', () {
      expect(text('uno<br>dos<br/>tres<BR />cuatro'), 'uno\ndos\ntres\ncuatro');
    });

    test('un <div> por línea no deja líneas en blanco de más', () {
      expect(text('<div>uno</div><div>dos</div>'), 'uno\ndos');
      expect(text('uno<div>dos</div>tres'), 'uno\ndos\ntres');
    });

    test('un <p> y un <br> seguidos dan una línea en blanco como mucho', () {
      expect(text('<p>uno</p><br><br><br><p>dos</p>'), 'uno\n\ndos');
    });

    test('las listas llevan guion', () {
      expect(
        text('Lista:<ul><li>uno</li><li>dos <b>2</b></li></ul>'),
        'Lista:\n- uno\n- dos **2**',
      );
    });

    test('un salto de línea de verdad en el texto se conserva', () {
      expect(text('uno\ndos'), 'uno\ndos');
      expect(text('uno\r\ndos'), 'uno\ndos');
    });
  });

  group('entidades', () {
    test('las nombradas, las numéricas y el espacio duro', () {
      expect(text('a&nbsp;b'), 'a b');
      expect(text('Tom &amp; Jerry'), 'Tom & Jerry');
      expect(
        text('&lt;b&gt; &quot;hola&quot; &#39;x&#39;'),
        '<b> "hola" \'x\'',
      );
      expect(text('caf&eacute; &#233; &#xE9; &ntilde;'), 'café é é ñ');
      expect(text('a&mdash;b &hellip; &laquo;x&raquo;'), 'a—b … «x»');
    });

    test('un & suelto o una entidad inventada no rompen', () {
      expect(text('a & b'), 'a & b');
      expect(text('&inventada; x'), '&inventada; x');
    });

    test('un "<" suelto es texto', () {
      expect(text('3 < 5 y 7 > 2'), '3 < 5 y 7 > 2');
    });
  });

  group('formato', () {
    test('negrita y cursiva como Markdown', () {
      expect(text('<b>uno</b> y <strong>dos</strong>'), '**uno** y **dos**');
      expect(text('<i>uno</i> y <em>dos</em>'), '*uno* y *dos*');
    });

    test('los espacios de los bordes quedan fuera de la marca', () {
      expect(text('a<b> hola </b>b'), 'a **hola** b');
    });

    test('una negrita vacía no deja ****', () {
      expect(text('a<b></b>b<b> </b>c'), 'ab c');
    });

    test('sin Markdown, el formato se pierde pero el texto no', () {
      expect(text('<b>uno</b> <i>dos</i>', markdown: false), 'uno dos');
    });

    test('lo que no es texto se descarta: estilos, scripts, comentarios', () {
      expect(
        text(
          '<style>.x{color:red}</style>hola<script>alert(1)</script>'
          '<!-- comentario -->',
        ),
        'hola',
      );
    });

    test('atributos, etiquetas desconocidas y spans se ignoran', () {
      expect(
        text(
          '<span style="color:red" class="x">rojo</span> '
          '<font color="#fff">blanco</font> <x-raro a="1">raro</x-raro>',
        ),
        'rojo blanco raro',
      );
    });

    test('espacios repetidos y a los bordes de la línea', () {
      expect(text('  uno    dos  \n  tres  '), 'uno dos\ntres');
    });

    test('HTML roto: etiquetas sin cerrar', () {
      // El navegador anida el segundo <div> dentro de la negrita; Markdown no
      // deja que una marca cruce líneas, así que cada línea lleva la suya.
      expect(text('<div><b>hola<div>chau'), '**hola**\n**chau**');
    });

    test('vacío', () {
      expect(text(''), '');
      expect(text('   '), '');
      expect(text('<br><div></div>'), '');
    });

    test('Unicode: acentos, ñ, emoji y otros alfabetos', () {
      expect(text('<b>niño 🧒🏽</b> Привет 漢字'), '**niño 🧒🏽** Привет 漢字');
    });

    test('los huecos de Anki pasan intactos', () {
      expect(
        text('El {{c1::<b>Imperio</b> romano::pista}} cayó', markdown: false),
        'El {{c1::Imperio romano::pista}} cayó',
      );
    });
  });

  group('medios', () {
    test('una imagen se cuenta y se saca del texto', () {
      final r = ankiHtmlToText('Mirá <img src="gato.jpg"> esto');

      expect(r.text, 'Mirá esto');
      expect(r.media, [const AnkiMediaRef('gato.jpg', AnkiMediaKind.image)]);
    });

    test('[sound:...] es audio, o video según la extensión', () {
      final r = ankiHtmlToText('hola [sound:voz.mp3] [sound:clip.mp4] chau');

      expect(r.text, 'hola chau');
      expect(r.media, const [
        AnkiMediaRef('voz.mp3', AnkiMediaKind.audio),
        AnkiMediaRef('clip.mp4', AnkiMediaKind.video),
      ]);
    });

    test('<audio>, <video> y <source>', () {
      final r = ankiHtmlToText(
        '<audio src="a.ogg"></audio><video><source src="v.webm"></video>',
      );

      expect(r.media, const [
        AnkiMediaRef('a.ogg', AnkiMediaKind.audio),
        AnkiMediaRef('v.webm', AnkiMediaKind.video),
      ]);
    });

    test('un audio dentro de <video> sigue siendo audio por su extensión', () {
      final r = ankiHtmlToText('<video src="canción.mp3"></video>');

      expect(r.media, const [AnkiMediaRef('canción.mp3', AnkiMediaKind.audio)]);
    });

    test('tres <br> seguidos dejan una sola línea en blanco', () {
      expect(text('uno<br><br><br>dos'), 'uno\n\ndos');
      expect(text('uno<br><br>dos'), 'uno\n\ndos');
    });

    test('el mismo medio dos veces cuenta una vez', () {
      final r = ankiHtmlToText('<img src="a.png"><img src="a.png">');

      expect(r.media, hasLength(1));
    });

    test('un nombre con espacios, acentos y emoji se conserva', () {
      final r = ankiHtmlToText('<img src="mi foto ñandú 🎉.png">');

      expect(r.media.single.name, 'mi foto ñandú 🎉.png');
    });

    test('una imagen sin src o con src vacío no cuenta', () {
      expect(ankiHtmlToText('<img>').media, isEmpty);
      expect(ankiHtmlToText('<img src="">').media, isEmpty);
    });

    test('solo una imagen: el texto queda vacío', () {
      final r = ankiHtmlToText('<img src="mapa.png">');

      expect(r.text, '');
      expect(r.media, hasLength(1));
    });
  });

  test('un campo enorme se convierte sin colgarse', () {
    final html = '${'<div>línea <b>x</b> &amp; y</div>' * 20000}fin';
    final watch = Stopwatch()..start();
    final r = ankiHtmlToText(html);
    watch.stop();

    expect(r.text.endsWith('fin'), isTrue);
    expect(r.text.split('\n'), hasLength(20001));
    expect(watch.elapsedMilliseconds, lessThan(15000));
  });
}
