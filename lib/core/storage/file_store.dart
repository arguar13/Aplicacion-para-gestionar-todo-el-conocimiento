import 'dart:convert';
import 'dart:typed_data';

/// Dónde viven los archivos originales.
///
/// Fuera de la base de datos, a propósito. SQLite guarda binarios sin
/// problema, pero un EPUB de treinta megas dentro de una fila hace lenta a
/// toda la tabla: cada consulta que la recorra —listar la biblioteca,
/// reconstruir el índice de búsqueda— arrastra esos megas aunque no los
/// necesite. Afuera, la base queda liviana y los archivos se leen solo cuando
/// alguien los abre.
///
/// Por qué existe esta interfaz y no se llama a `dart:io` directamente: para
/// que el resto de la app no sepa dónde están los archivos ni cómo se
/// nombran, y para poder probar todo lo que los usa sin tocar el disco real
/// del usuario.
abstract interface class FileStore {
  /// Guarda lo que va llegando por [bytes], por partes, y devuelve la **ruta
  /// relativa** donde quedó — lo mismo que [save], sin tener nunca el archivo
  /// entero en memoria.
  ///
  /// Es lo que permite guardar un video de varios GB grabado con el teléfono,
  /// o el audio de un video de cuatro horas (F21): con [save] habría que
  /// tenerlo entero en memoria primero. Si [bytes] falla a mitad de camino,
  /// no queda un archivo a medias: se borra lo escrito y se relanza el error.
  ///
  /// [folder] lo guarda en una subcarpeta de la del elemento —el «Contenido»
  /// bajado de una página va en `originales/<id>/contenido/` (F30)—: un solo
  /// tramo, saneado como un nombre. Con [unique], un nombre que ya está no se
  /// pisa: el archivo nuevo queda como "nombre-2.ext", "nombre-3.ext"…
  /// Una página puede ofrecer dos `foto.jpg` de carpetas distintas, y sin
  /// esto la segunda borraba la primera.
  Future<String> saveStream({
    required Stream<List<int>> bytes,
    required String suggestedName,
    required String id,
    String? folder,
    bool unique = false,
  });

  /// Guarda [bytes] y devuelve la **ruta relativa** donde quedaron.
  ///
  /// [suggestedName] es el nombre que traía el archivo. Se usa solo para que
  /// la carpeta sea legible si alguien la abre; no se confía en él (ver
  /// [sanitizeFileName]).
  Future<String> save({
    required Uint8List bytes,
    required String suggestedName,
    required String id,
  });

  /// Los bytes guardados en [relativePath], o `null` si ya no están.
  ///
  /// Que falte no es un fallo del programa: alguien pudo vaciar el
  /// almacenamiento de la app desde los ajustes del sistema. El elemento
  /// sigue existiendo con su texto ya extraído; lo único que se perdió es la
  /// copia del original.
  Future<Uint8List?> read(String relativePath);

  /// Los primeros [maxBytes] bytes de lo guardado en [relativePath], o
  /// `null` si ya no está — para reconocer el formato de un archivo sin
  /// cargarlo entero en memoria.
  ///
  /// Separado de [read] por el mismo motivo que [exists]: un video o un PDF
  /// de varios cientos de megas no tiene por qué pasar completo por acá
  /// solo para confirmar, por ejemplo, que es un `.mp4` — con los primeros
  /// bytes alcanza.
  Future<Uint8List?> readHead(String relativePath, {int maxBytes = 4096});

  /// Hasta [length] bytes de lo guardado en [relativePath] a partir de
  /// [start] —menos si el archivo termina antes—, o `null` si ya no está.
  ///
  /// Para leer una parte de un archivo grande sin traerlo entero: los
  /// metadatos de un PDF de varios cientos de megas están al principio y al
  /// final, no en el medio (F21).
  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int length,
  });

  /// Cuánto pesa lo guardado en [relativePath], en bytes, o `null` si ya no
  /// está. Sin leerlo.
  Future<int?> sizeOf(String relativePath);

  /// La ruta de [relativePath] en el sistema de archivos del dispositivo, si
  /// el archivo vive en uno —para abrirlo desde el disco en vez de pasarlo
  /// por memoria—, o `null` si no: en la web vive en OPFS, donde no hay una
  /// ruta que otra librería pueda abrir.
  ///
  /// Distinto de [resolve], que siempre devuelve algo —en la web, una ruta
  /// dentro de OPFS—: esto solo devuelve una ruta abrible con `dart:io`.
  Future<String?> localPathOf(String relativePath);

  /// Si [relativePath] todavía está guardado, sin leer su contenido.
  ///
  /// Separado de [read] a propósito: un transformador que solo necesita
  /// comprobar que el archivo sigue estando —porque lo que va a usar
  /// después es la ruta absoluta, no los bytes— no tiene por qué cargar en
  /// memoria un audio o un video de cientos de megas solo para descartarlo.
  Future<bool> exists(String relativePath);

  /// La ruta absoluta actual de [relativePath], para abrir el archivo con la
  /// app del sistema o compartirlo.
  Future<String> resolve(String relativePath);

  /// Borra lo guardado. No falla si no estaba.
  Future<void> delete(String relativePath);
}

/// Deja un nombre de archivo en algo seguro de escribir en el disco.
///
/// No es cosmética: el nombre puede venir de otra aplicación —del botón de
/// compartir de cualquier app instalada— y eso lo vuelve entrada no confiable.
/// Un nombre como `../../databases/sinapsis.db` escrito tal cual saldría de la
/// carpeta del almacén y pisaría la base de datos del usuario. Por eso se
/// descarta todo lo que no esté explícitamente permitido, en vez de intentar
/// reconocer patrones peligrosos uno por uno: lo que no está en la lista de
/// permitidos, no pasa.
///
/// Lo permitido son **letras y números de cualquier alfabeto**, más espacio,
/// punto, guion y guion bajo. Las letras acentuadas entran: esta app se usa
/// en español, y convertir `biología.pdf` en `biolog_a.pdf` sería romper algo
/// que no hacía falta romper. Ninguna letra es un separador de rutas, así que
/// aceptarlas no abre ninguna puerta.
///
/// Se expone para poder probarlo por su cuenta. Lo que decide acá es la
/// diferencia entre guardar un archivo y darle a cualquier app instalada la
/// capacidad de escribir donde quiera.
String sanitizeFileName(String raw) {
  // Cualquier carácter que no sea letra, número, espacio, punto, guion o
  // guion bajo —barras, dos puntos de Windows, bytes de control, saltos de
  // línea— se vuelve un guion bajo.
  final cleaned = raw.replaceAll(
    RegExp(r'[^\p{L}\p{N} ._-]', unicode: true),
    '_',
  );

  // Los puntos seguidos son la forma clásica de subir de directorio, y
  // sobreviven al filtro anterior porque el punto sí está permitido: hace
  // falta para la extensión.
  final withoutTraversal = cleaned.replaceAll(RegExp(r'\.{2,}'), '_');

  // Un nombre que empieza con punto queda oculto en los sistemas Unix, y uno
  // con espacios al borde confunde a las herramientas de línea de comandos.
  final trimmed = withoutTraversal.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');

  // Un nombre que era puro separador queda en algo como `___`: técnicamente
  // válido y completamente inútil. Se exige al menos una letra o un número
  // para considerarlo un nombre.
  if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(trimmed)) {
    return 'archivo';
  }

  return _truncateKeepingExtension(trimmed, 120);
}

/// Recorta a [maxBytes] **bytes de UTF-8**, no a caracteres.
///
/// Los sistemas de archivos miden en bytes: el límite habitual de 255 lo
/// alcanzan 255 letras latinas, pero solo 85 ideogramas. Contar caracteres
/// funcionaría en español y fallaría en japonés. Y el corte va siempre en el
/// borde de un carácter: partir una secuencia UTF-8 por la mitad produce un
/// nombre inválido.
///
/// La extensión se conserva porque es lo que decide con qué app se abre el
/// archivo.
String _truncateKeepingExtension(String name, int maxBytes) {
  if (utf8.encode(name).length <= maxBytes) return name;

  final dot = name.lastIndexOf('.');
  // Sin extensión reconocible —o con una absurdamente larga, que entonces no
  // es una extensión— se corta a secas.
  final hasExtension = dot > 0 && name.length - dot <= 12;

  final extension = hasExtension ? name.substring(dot) : '';
  final base = hasExtension ? name.substring(0, dot) : name;
  final budget = maxBytes - utf8.encode(extension).length;

  final buffer = StringBuffer();
  var used = 0;
  for (final rune in base.runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    if (used + size > budget) break;

    buffer.write(character);
    used += size;
  }

  return buffer.toString() + extension;
}

/// El nombre [attempt] de la serie de [name] que no pisa a otro: el mismo
/// en el primer intento, y después "nombre-2.ext", "nombre-3.ext"… —sin
/// paréntesis: no están entre los caracteres que deja [sanitizeFileName]—.
///
/// La extensión se conserva —decide con qué app se abre— y el número va
/// antes. Ya saneado y recortado: lo que devuelve se escribe tal cual.
String numberedFileName(String name, int attempt) {
  if (attempt <= 1) return name;
  final dot = name.lastIndexOf('.');
  final hasExtension = dot > 0 && name.length - dot <= 12;
  final stem = hasExtension ? name.substring(0, dot) : name;
  final extension = hasExtension ? name.substring(dot) : '';
  return sanitizeFileName('$stem-$attempt$extension');
}
