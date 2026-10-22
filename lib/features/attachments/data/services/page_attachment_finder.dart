import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';

/// Lo más que se anota de una página: una galería de mil fotos no puede
/// convertir un artículo en mil bajadas.
const kMaxPageAttachments = 300;

/// Lo que ofrece el cuerpo de un artículo para bajar (F30, decisión D), en el
/// orden en que aparece:
///
/// - **Las fotos**, en su versión más grande —la de la carga diferida, la
///   de su `srcset` o la de un `<source>` de su `<picture>`, o su `src`:
///   ver `bestImageSource`—. Los SVG también.
/// - **Los archivos enlazados**: un `<a href>` que apunta a un PDF, un EPUB,
///   un Word, un audio, un video, una foto o un `.zip`. Un enlace que solo
///   envuelve una foto no cuenta —la foto ya está, y en Wikipedia ese
///   enlace lleva a la página de la foto, no a la foto—.
/// - **Los videos y audios incrustados**: `<video>`, `<audio>` y su primer
///   `<source>`, y lo que se incruste con `<embed>` u `<object>`.
///
/// Solo del cuerpo del artículo: [articleHtml] es lo que dejó el modo
/// lectura, sin menú, barra lateral ni pie. Las direcciones ya vienen
/// completas (ver `page_urls.dart`); lo que no es http o https no se
/// anota.
///
/// Se dejan afuera los íconos y los píxeles de seguimiento —una imagen que
/// dice medir 64 px o menos de cada lado, o 2 px o menos de alguno—, las
/// imágenes incrustadas como `data:` y lo repetido (la misma dirección, sin
/// su `#ancla`).
List<AttachmentCandidate> findPageAttachments(
  String articleHtml, {
  int maxCandidates = kMaxPageAttachments,
}) {
  final fragment = html_parser.parseFragment(articleHtml);
  final found = <AttachmentCandidate>[];
  final seen = <String>{};

  void add(String? reference, RenditionKind kind, String? title) {
    if (reference == null || found.length >= maxCandidates) return;
    final url = _webUrl(reference);
    if (url == null) return;
    if (!seen.add(_sameFileKey(url))) return;
    found.add(
      AttachmentCandidate(
        url: url.removeFragment(),
        kind: kind,
        position: found.length,
        title: title,
      ),
    );
  }

  for (final element in fragment.querySelectorAll('*')) {
    if (found.length >= maxCandidates) break;
    switch (element.localName) {
      case 'img':
        if (_isDecoration(element)) continue;
        add(
          bestImageSource(element, size: ImageSize.largest),
          RenditionKind.image,
          _imageTitle(element),
        );
      case 'a':
        final href = element.attributes['href'];
        final url = href == null ? null : _webUrl(href);
        if (url == null) continue;
        final kind = mediaKindOfUrl(url);
        if (kind == null) continue;
        if (_onlyWrapsAnImage(element)) continue;
        add(href, kind, _textOf(element));
      case 'video' || 'audio':
        final kind = element.localName == 'video'
            ? RenditionKind.video
            : RenditionKind.audio;
        final source =
            element.attributes['src'] ??
            element.children
                .where((c) => c.localName == 'source')
                .map((c) => c.attributes['src'])
                .nonNulls
                .firstOrNull;
        add(source, kind, _mediaTitle(element));
      case 'embed' || 'object':
        final source = element.localName == 'embed'
            ? element.attributes['src']
            : element.attributes['data'];
        final url = source == null ? null : _webUrl(source);
        final kind = url == null ? null : mediaKindOfUrl(url);
        if (kind != null) add(source, kind, element.attributes['title']);
    }
  }
  return found;
}

/// Lo que hace que dos direcciones sean el mismo archivo: sin su `#ancla`,
/// sin importar si es http o https, y sin el envoltorio del Internet
/// Archive. Las referencias de Wikipedia enlazan cada PDF dos veces —el
/// original y su copia en `web.archive.org/web/<fecha>/<original>`—, y
/// bajarlo dos veces no suma nada.
String _sameFileKey(Uri url) {
  var address = url.removeFragment().toString();
  final wayback = RegExp(
    r'^https?://web\.archive\.org/web/\d+[a-z_]*/(.+)$',
  ).firstMatch(address);
  if (wayback != null) address = wayback[1]!;
  return address.replaceFirst(RegExp('^https?://'), '');
}

/// [reference] como dirección web completa, o `null`.
Uri? _webUrl(String reference) {
  final trimmed = reference.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) return null;
  final Uri url;
  try {
    url = Uri.parse(trimmed);
  } on FormatException {
    return null;
  }
  if (url.scheme != 'http' && url.scheme != 'https') return null;
  if (url.host.isEmpty) return null;
  return url;
}

/// Un ícono, un píxel de seguimiento o algo que dice que es decoración.
bool _isDecoration(dom.Element img) {
  int? dimension(String name) => int.tryParse(
    (img.attributes[name] ?? '').trim().replaceFirst(RegExp(r'px$'), ''),
  );
  final width = dimension('width');
  final height = dimension('height');
  if ((width != null && width <= 2) || (height != null && height <= 2)) {
    return true;
  }
  if (width != null && height != null && width <= 64 && height <= 64) {
    return true;
  }
  if (width != null && height == null && width <= 48) return true;
  if (height != null && width == null && height <= 48) return true;
  return img.attributes['role'] == 'presentation' ||
      img.attributes['aria-hidden'] == 'true';
}

/// Si el enlace no tiene más contenido que una foto.
bool _onlyWrapsAnImage(dom.Element anchor) =>
    anchor.querySelector('img, picture, svg') != null &&
    anchor.text.trim().isEmpty;

String? _imageTitle(dom.Element img) =>
    _clean(img.attributes['alt']) ?? _figureCaption(img);

String? _mediaTitle(dom.Element media) =>
    _clean(media.attributes['title']) ??
    _clean(media.attributes['aria-label']) ??
    _figureCaption(media);

String? _figureCaption(dom.Element element) {
  var current = element.parent;
  for (var depth = 0; current != null && depth < 4; depth++) {
    if (current.localName == 'figure') {
      return _clean(current.querySelector('figcaption')?.text);
    }
    current = current.parent;
  }
  return null;
}

String? _textOf(dom.Element element) => _clean(element.text);

/// Sin los espacios de formato del HTML y recortado: es un nombre, no un
/// párrafo.
String? _clean(String? text) {
  if (text == null) return null;
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  return collapsed.length <= 160
      ? collapsed
      : '${collapsed.substring(0, 159).trimRight()}…';
}
