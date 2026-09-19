import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'content_block.freezed.dart';

/// Un bloque de una nota armada con bloques, al estilo de Notion: encabezado,
/// párrafo, ítem de lista, casillero o cita.
///
/// Sellado y no un solo `ContentBlock(type: ..., text: ...)` para que el
/// compilador exija cubrir cada tipo en el editor y en la vista de lectura —
/// agregar un tipo nuevo hace que `switch` sin `default` marque en rojo cada
/// lugar que todavía no lo contempla, en vez de fallar en silencio con un
/// bloque que no se ve.
///
/// Cada bloque puede recordar cuándo se agregó (`addedAt`): es lo que permite
/// saber qué notas crecieron esta semana. Es opcional y compatible hacia
/// atrás: un bloque de antes no lo trae y se lee con `null`, y un `null` no se
/// escribe, así que una nota que no se toca guarda exactamente el mismo JSON
/// que antes.
@freezed
sealed class ContentBlock with _$ContentBlock {
  const factory ContentBlock.paragraph({
    required String text,
    DateTime? addedAt,
  }) = ParagraphBlock;

  /// [level] es 1 o 2 — dos niveles alcanzan para estructurar una nota; un
  /// tercero solo tendría sentido en documentos mucho más largos que lo que
  /// esta app espera que alguien escriba a mano.
  const factory ContentBlock.heading({
    required String text,
    @Default(1) int level,
    DateTime? addedAt,
  }) = HeadingBlock;

  const factory ContentBlock.bulletItem({
    required String text,
    DateTime? addedAt,
  }) = BulletItemBlock;

  const factory ContentBlock.numberedItem({
    required String text,
    DateTime? addedAt,
  }) = NumberedItemBlock;

  const factory ContentBlock.checklistItem({
    required String text,
    @Default(false) bool checked,
    DateTime? addedAt,
  }) = ChecklistItemBlock;

  const factory ContentBlock.quote({required String text, DateTime? addedAt}) =
      QuoteBlock;

  const ContentBlock._();

  /// El texto del bloque, sea cual sea su tipo. Para buscar y para saber si
  /// un bloque quedó vacío.
  @override
  String get text => switch (this) {
    ParagraphBlock(:final text) => text,
    HeadingBlock(:final text) => text,
    BulletItemBlock(:final text) => text,
    NumberedItemBlock(:final text) => text,
    ChecklistItemBlock(:final text) => text,
    QuoteBlock(:final text) => text,
  };

  /// Cuándo se agregó el bloque a la nota, sea cual sea su tipo. `null` en un
  /// bloque de antes de que se guardara la fecha: no se sabe cuándo nació, y
  /// no se inventa.
  @override
  DateTime? get addedAt => switch (this) {
    ParagraphBlock(:final addedAt) => addedAt,
    HeadingBlock(:final addedAt) => addedAt,
    BulletItemBlock(:final addedAt) => addedAt,
    NumberedItemBlock(:final addedAt) => addedAt,
    ChecklistItemBlock(:final addedAt) => addedAt,
    QuoteBlock(:final addedAt) => addedAt,
  };
}

const _typeParagraph = 'paragraph';
const _typeHeading = 'heading';
const _typeBulletItem = 'bulletItem';
const _typeNumberedItem = 'numberedItem';
const _typeChecklistItem = 'checklistItem';
const _typeQuote = 'quote';

/// Los bloques de una nota, como el `content` que guarda una
/// `Rendition.text` de tipo `RenditionKind.blocks`.
///
/// JSON a mano y no `@JsonSerializable` sobre la clase `@freezed`: el
/// resto de las entidades selladas del proyecto no necesitan serializarse
/// —solo esta, porque es la única que se guarda como texto en una columna
/// pensada para texto— y sumar `json_serializable` encima de `freezed` para
/// una sola clase es más superficie nueva que estas pocas líneas.
String encodeContentBlocks(List<ContentBlock> blocks) {
  return jsonEncode(blocks.map(_blockToJson).toList());
}

/// El inverso de [encodeContentBlocks]. Un bloque de un tipo que esta
/// versión no reconoce —de una futura que agregue uno nuevo— se lee como un
/// párrafo con su texto tal cual, en vez de hacer fallar la nota entera:
/// degradar antes que fallar, igual que el resto de la app.
List<ContentBlock> decodeContentBlocks(String json) {
  final decoded = jsonDecode(json) as List<dynamic>;
  return decoded
      .map((raw) => _blockFromJson(raw as Map<String, dynamic>))
      .toList();
}

/// Como [decodeContentBlocks], pero TOTAL: devuelve `null` si [json] no son
/// bloques legibles —no es JSON, no es una lista, o algún campo tiene otro
/// tipo— en vez de lanzar.
///
/// Para quien recorre notas de a miles y no puede caerse por una: la
/// migración que registra los enlaces, por ejemplo. Un `null` acá es "esta
/// nota no se pudo leer", algo para informar, no para tragarse.
List<ContentBlock>? tryDecodeContentBlocks(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! List<dynamic>) return null;

  final blocks = <ContentBlock>[];
  for (final raw in decoded) {
    if (raw is! Map<String, dynamic>) return null;
    if (raw['text'] != null && raw['text'] is! String) return null;
    if (raw['level'] != null && raw['level'] is! int) return null;
    if (raw['checked'] != null && raw['checked'] is! bool) return null;
    if (raw['addedAt'] != null && raw['addedAt'] is! String) return null;
    blocks.add(_blockFromJson(raw));
  }
  return blocks;
}

const _keyAddedAt = 'addedAt';

Map<String, dynamic> _blockToJson(ContentBlock block) {
  final json = switch (block) {
    ParagraphBlock(:final text) => {'type': _typeParagraph, 'text': text},
    HeadingBlock(:final text, :final level) => {
      'type': _typeHeading,
      'text': text,
      'level': level,
    },
    BulletItemBlock(:final text) => {'type': _typeBulletItem, 'text': text},
    NumberedItemBlock(:final text) => {'type': _typeNumberedItem, 'text': text},
    ChecklistItemBlock(:final text, :final checked) => {
      'type': _typeChecklistItem,
      'text': text,
      'checked': checked,
    },
    QuoteBlock(:final text) => {'type': _typeQuote, 'text': text},
  };

  // Un `null` no se escribe: una nota que no se toca guarda el mismo JSON de
  // siempre. En UTC, para que la misma fecha no dependa de dónde se guardó.
  final addedAt = block.addedAt;
  if (addedAt != null) json[_keyAddedAt] = addedAt.toUtc().toIso8601String();
  return json;
}

ContentBlock _blockFromJson(Map<String, dynamic> json) {
  final text = json['text'] as String? ?? '';
  // Una fecha que no se puede leer degrada a "no se sabe cuándo": la nota
  // sigue abriéndose.
  final addedAt = DateTime.tryParse(json[_keyAddedAt] as String? ?? '');

  return switch (json['type']) {
    _typeHeading => ContentBlock.heading(
      text: text,
      level: json['level'] as int? ?? 1,
      addedAt: addedAt,
    ),
    _typeBulletItem => ContentBlock.bulletItem(text: text, addedAt: addedAt),
    _typeNumberedItem => ContentBlock.numberedItem(
      text: text,
      addedAt: addedAt,
    ),
    _typeChecklistItem => ContentBlock.checklistItem(
      text: text,
      checked: json['checked'] as bool? ?? false,
      addedAt: addedAt,
    ),
    _typeQuote => ContentBlock.quote(text: text, addedAt: addedAt),
    _ => ContentBlock.paragraph(text: text, addedAt: addedAt),
  };
}
