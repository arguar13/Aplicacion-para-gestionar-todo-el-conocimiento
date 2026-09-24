import 'package:path/path.dart' as p;
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

/// El nombre del archivo que menciona el campo `file` de un `.bib` (JabRef,
/// Zotero) o el `L1` de un `.ris` (F15, D14): solo el nombre, nunca la ruta
/// —la ruta era del dispositivo que exportó el archivo—.
///
/// Ninguno de los dos formatos tiene una sintaxis simple y única: JabRef
/// escribe `file = {descripción:C:\ruta\archivo.pdf:PDF}` (una ruta de
/// Windows adentro, con su propio `:` de la unidad, dentro de un campo que
/// YA usa `:` como separador), Zotero a veces solo la ruta pelada, y RIS no
/// dice nada más que «un enlace que debería terminar en un nombre de
/// archivo». En vez de parsear cada convención a mano —frágil, y nunca
/// completo—, se busca la porción del texto que termina en una extensión de
/// documento conocida, sin `:` ni `;` en el medio —los separadores que usan
/// las dos convenciones—, y se toma su nombre de archivo. Encuentra el
/// mismo resultado aunque la ruta tenga la unidad de Windows adentro: el
/// primer tramo sin esos separadores que termina en la extensión.
String? extractAttachmentFileName(String raw) {
  final match = _attachmentPath.firstMatch(raw);
  if (match == null) return null;

  final name = p.basename(match.group(0)!.trim());
  return name.isEmpty ? null : name;
}

final _attachmentPath = RegExp(
  r'[^:;]+\.(?:pdf|docx?|epub|txt|md)',
  caseSensitive: false,
);

/// El archivo, entre [chosenFiles] —los que se eligieron junto con el
/// `.bib`/`.ris` (F15, D14)—, cuyo nombre coincide con [attachmentFileName],
/// sin distinguir mayúsculas —como ya hacen Windows y macOS con los nombres
/// de archivo—, o `null` si no se eligió ninguno con ese nombre.
CapturedFile? matchAttachmentFile(
  String? attachmentFileName,
  List<CapturedFile> chosenFiles,
) {
  if (attachmentFileName == null) return null;

  final target = attachmentFileName.toLowerCase();
  for (final file in chosenFiles) {
    if (file.name.toLowerCase() == target) return file;
  }
  return null;
}
