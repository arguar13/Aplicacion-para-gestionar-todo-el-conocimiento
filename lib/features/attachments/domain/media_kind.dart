import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/util/lenient_uri.dart';

/// Qué es un archivo, por el tipo que dijo el servidor y por su nombre (F30):
/// un PDF, otro documento, una foto, un audio, un video, otra clase de
/// archivo —[RenditionKind.file]: un `.zip`, un `.mobi`—, o `null` si es una
/// página web.
///
/// Manda el tipo del servidor; el nombre decide cuando el servidor no dice
/// nada útil (`application/octet-stream`, `binary/octet-stream`, nada).
RenditionKind? mediaKindOf({required String fileName, String? contentType}) {
  final mime = contentType?.split(';').first.trim().toLowerCase();
  final byType = mime == null ? null : _byMime(mime);
  if (byType != null) return byType.kind;
  final extension = p.extension(fileName).toLowerCase();
  // Una extensión de página (`.html`, `.php`) dice que es una página.
  if (_byExtension.containsKey(extension)) return _byExtension[extension];
  return mime == null || _generic.contains(mime) ? RenditionKind.file : null;
}

/// Si es un `.zip`: lo que se descomprime solo.
bool isZipArchive({required String fileName, String? contentType}) {
  final mime = contentType?.split(';').first.trim().toLowerCase();
  if (mime == 'application/zip' || mime == 'application/x-zip-compressed') {
    return true;
  }
  return p.extension(fileName).toLowerCase() == '.zip' &&
      (mime == null || _generic.contains(mime));
}

/// Si es un documento del que la app sabe sacar el texto (los lectores de
/// `DocumentParser`): PDF, EPUB, Word, texto y Markdown. Un `.doc` viejo o un
/// `.odt` se guardan igual, pero como archivo.
bool isReadableDocument({required String fileName, String? contentType}) {
  final mime = contentType?.split(';').first.trim().toLowerCase();
  if (mime != null && _readableMimes.contains(mime)) return true;
  return _readableExtensions.contains(p.extension(fileName).toLowerCase()) &&
      (mime == null || _generic.contains(mime) || mime.startsWith('text/'));
}

const _generic = {
  'application/octet-stream',
  'binary/octet-stream',
  'application/x-download',
  'application/download',
  'application/force-download',
};

const _readableMimes = {
  'application/pdf',
  'application/epub+zip',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'text/plain',
  'text/markdown',
  'text/x-markdown',
};

const _readableExtensions = {
  '.pdf',
  '.epub',
  '.docx',
  '.txt',
  '.md',
  '.markdown',
};

({RenditionKind? kind})? _byMime(String mime) {
  if (mime == 'text/html' || mime == 'application/xhtml+xml') {
    return (kind: null);
  }
  if (mime == 'application/pdf') return (kind: RenditionKind.pdf);
  if (_readableMimes.contains(mime) ||
      mime == 'application/msword' ||
      mime == 'application/rtf' ||
      mime == 'application/vnd.oasis.opendocument.text') {
    return (kind: RenditionKind.document);
  }
  if (mime.startsWith('image/')) return (kind: RenditionKind.image);
  if (mime.startsWith('audio/') || mime == 'application/ogg') {
    return (kind: RenditionKind.audio);
  }
  if (mime.startsWith('video/')) return (kind: RenditionKind.video);
  if (mime == 'application/zip' || mime == 'application/x-zip-compressed') {
    return (kind: RenditionKind.file);
  }
  if (_generic.contains(mime)) return null;
  // Otro tipo de texto (CSS, JavaScript, XML de un feed) no es ni un archivo
  // para guardar ni una página: lo decide el nombre.
  if (mime.startsWith('text/')) return null;
  return (kind: RenditionKind.file);
}

const _byExtension = <String, RenditionKind?>{
  '.pdf': RenditionKind.pdf,
  '.epub': RenditionKind.document,
  '.docx': RenditionKind.document,
  '.doc': RenditionKind.document,
  '.odt': RenditionKind.document,
  '.rtf': RenditionKind.document,
  '.txt': RenditionKind.document,
  '.md': RenditionKind.document,
  '.markdown': RenditionKind.document,
  '.jpg': RenditionKind.image,
  '.jpeg': RenditionKind.image,
  '.png': RenditionKind.image,
  '.gif': RenditionKind.image,
  '.webp': RenditionKind.image,
  '.svg': RenditionKind.image,
  '.avif': RenditionKind.image,
  '.heic': RenditionKind.image,
  '.bmp': RenditionKind.image,
  '.mp3': RenditionKind.audio,
  '.m4a': RenditionKind.audio,
  '.aac': RenditionKind.audio,
  '.ogg': RenditionKind.audio,
  '.oga': RenditionKind.audio,
  '.opus': RenditionKind.audio,
  '.wav': RenditionKind.audio,
  '.flac': RenditionKind.audio,
  '.mp4': RenditionKind.video,
  '.m4v': RenditionKind.video,
  '.mov': RenditionKind.video,
  '.webm': RenditionKind.video,
  '.mkv': RenditionKind.video,
  '.3gp': RenditionKind.video,
  '.zip': RenditionKind.file,
  '.html': null,
  '.htm': null,
  '.php': null,
  '.asp': null,
  '.aspx': null,
  '.jsp': null,
};

/// La clase de archivo que sugiere [url] por su extensión, o `null` si no
/// sugiere ninguna —una página, o una dirección sin extensión—. Es lo que se
/// sabe de un enlace antes de pedirlo.
RenditionKind? mediaKindOfUrl(Uri url) {
  final last = lastPathSegmentOf(url);
  if (last == null) return null;
  return _byExtension[p.extension(last).toLowerCase()];
}

/// Si la respuesta a pedir una dirección es un archivo y no una página: lo
/// que dice el servidor, y si no dice nada útil, la extensión del nombre.
/// Una respuesta sin tipo y sin extensión conocida se trata como página,
/// que es lo que era antes de F30.
bool isFileResponse({required String fileName, String? contentType}) {
  final mime = contentType?.split(';').first.trim().toLowerCase();
  if (mime == null || mime.isEmpty || _generic.contains(mime)) {
    return _byExtension[p.extension(fileName).toLowerCase()] != null;
  }
  return mediaKindOf(contentType: mime, fileName: fileName) != null;
}
