// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/services/marked_document_writer.dart';

/// Un escritor de tramos marcados de mentira (F38): anota lo que se le pidió
/// y devuelve bytes reconocibles, sin tocar ningún archivo de verdad.
class FakeMarkedDocumentWriter implements MarkedDocumentWriter {
  FakeMarkedDocumentWriter({this.error});

  /// Si está, se lanza en vez de escribir.
  Object? error;

  Uint8List? lastOriginal;
  String? lastContent;
  List<DocumentMark>? lastMarks;
  int calls = 0;

  /// Lo que "escribe": el texto `marcado:<cuántos tramos>`.
  static Uint8List outputFor(int marks) =>
      Uint8List.fromList(utf8.encode('marcado:$marks'));

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
  }) async {
    calls++;
    if (error != null) throw error!;
    lastOriginal = original;
    lastContent = content;
    lastMarks = marks;
    return outputFor(marks.length);
  }
}
