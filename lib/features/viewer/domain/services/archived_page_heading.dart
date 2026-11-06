import 'dart:convert';

import 'package:html/dom.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';

/// Un título de una página web archivada al que se va al abrirla (F46, paso
/// 4): «Abrir en el original» desde un capítulo del Índice.
///
/// `title` es el del capítulo, como lo guardó el Índice; `occurrence`, cuántos
/// títulos iguales a él vienen antes en el documento —el segundo
/// «Referencias» es el segundo de la página—.
typedef ArchivedHeading = ({String title, int occurrence});

/// El `id` del título marcado.
const archivedHeadingId = 'sn-heading';

/// Lo que una página le agrega a un título entre corchetes y la extracción
/// no guarda: el `[editar]` de una enciclopedia, la llamada `[1]` a una nota.
final _bracketed = RegExp(r'\[[^\]]*\]');

/// Los encabezados de una página, en el orden en que se leen.
const _headingTags = 'h1, h2, h3, h4, h5, h6, [role="heading"]';

/// Marca en [document] el encabezado de [heading]: el `h1`…`h6` cuyo texto,
/// comparado sin mayúsculas, acentos ni puntuación (`headingKey`, la misma
/// regla con que el Índice ubica un marcador en el texto), es el del
/// capítulo. Si hay varios iguales, el de su lugar (`occurrence`); si la
/// página tiene menos —el texto procesado tenía uno que
/// la página repite en otro lado—, el primero. Devuelve si encontró uno.
///
/// Se busca por el título y no por la posición en el texto: el original es la
/// página de la fuente, y el texto procesado pudo perder pedazos al triarlo o
/// editarse después. El título es lo que los dos comparten.
bool markArchivedHeading(Document document, ArchivedHeading heading) {
  final wanted = headingKey(heading.title);
  if (wanted.isEmpty) return false;
  final matches = [
    for (final element in document.querySelectorAll(_headingTags))
      if (headingKey(element.text.replaceAll(_bracketed, '')) == wanted)
        element,
  ];
  if (matches.isEmpty) return false;
  final occurrence = heading.occurrence;
  final target = occurrence >= 0 && occurrence < matches.length
      ? matches[occurrence]
      : matches.first;
  // Un `id` que la página ya usaba para otra cosa se suelta: el de la app
  // tiene que ser uno solo.
  for (final other in document.querySelectorAll('#$archivedHeadingId')) {
    other.attributes.remove('id');
  }
  target.attributes['id'] = archivedHeadingId;
  return true;
}

/// El programa chico que, al terminar de cargarse la página —con sus fotos,
/// que corren lo de abajo—, deja el título marcado arriba de lo que se ve, a
/// [landing] del alto, y lo resalta dos segundos con [flash] (`0xAARRGGBB`).
/// Con [still] («sin animaciones») salta y el resalte se apaga de una.
void injectArchivedHeadingReveal(
  Document document, {
  required int flash,
  required double landing,
  required bool still,
}) {
  final color = '#${(flash & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final fade = still ? '' : 'transition:background-color .6s ease-out;';
  document.head?.append(
    Element.tag('style')
      ..attributes['id'] = 'sinapsis-heading'
      ..append(
        Text(
          '#$archivedHeadingId{scroll-margin-top:0;$fade}'
          '#$archivedHeadingId.sn-hf{background-color:$color!important;'
          'color:#000!important}',
        ),
      ),
  );
  final options = jsonEncode({'landing': landing, 'smooth': !still});
  document.body?.append(
    Element.tag('script')
      ..attributes['id'] = 'sinapsis-heading-script'
      ..append(Text(_revealScript(options))),
  );
}

String _revealScript(String options) =>
    '''
(function () {
  var o = $options;
  function go() {
    var el = document.getElementById('$archivedHeadingId');
    if (!el) return;
    var top = el.getBoundingClientRect().top;
    window.scrollBy({
      top: top - window.innerHeight * o.landing,
      left: 0,
      behavior: o.smooth ? 'smooth' : 'auto'
    });
    el.classList.add('sn-hf');
    setTimeout(function () { el.classList.remove('sn-hf'); }, 2000);
  }
  if (document.readyState === 'complete') go();
  else window.addEventListener('load', go);
})();
''';
