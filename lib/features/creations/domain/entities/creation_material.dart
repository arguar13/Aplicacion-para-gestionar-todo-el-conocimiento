import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';

/// Caracteres por token con que se estima lo que se le manda al modelo: tres,
/// como `estimateCloudTokens` (F32). Un poco más que lo que cuenta de verdad
/// un tokenizador en español (~3,5), a propósito: lo que se estima de menos
/// no entra en la ventana; lo que se estima de más solo deja un margen.
const kCreationCharsPerToken = 3;

/// Lo que se reserva en la ventana, además del material y de la respuesta,
/// para la instrucción, el esquema y las marcas de turno: unas 450 palabras.
/// Alcanza con Gemma (2048 tokens en total) si el esquema de cada tipo es
/// breve; uno más largo lo dice en su [CreationBudget.instructionTokens].
const kCreationInstructionTokens = 600;

/// Lo más que se manda de una vez aunque la ventana dé para más: ~117.000
/// tokens, un libro mediano. Más que esto gasta de golpe el tope por minuto de
/// la capa gratis de Gemini (250.000 tokens) con un solo pedido, y la espera
/// de leerlo pasa del minuto. Un libro más largo va por su resumen, su
/// síntesis o por partes.
const kMaxCreationInputChars = 350000;

/// Cuántas partes se leen, como mucho, por partes: con Gemma en el teléfono,
/// una parte son unos 40 segundos —unos 16 minutos el todo—. Si el texto da
/// más, se leen partes repartidas a lo largo de todo el texto, en orden
/// ([CreationMaterial.coverage] dice cuánto se leyó de primera mano).
const kMaxCreationParts = 24;

/// Lo que se estima que ocupan [chars] caracteres en la ventana del modelo.
int estimateCreationTokens(int chars) =>
    (chars / kCreationCharsPerToken).ceil();

/// Cuánto entra en la ventana del modelo elegido para una creación (F43, punto
/// 6 del plan): el material, la instrucción y la respuesta.
@immutable
class CreationBudget {
  const CreationBudget({
    required this.contextTokens,
    required this.reservedOutputTokens,
    this.instructionTokens = kCreationInstructionTokens,
  });

  /// La ventana del modelo (`ModelBackend.contextTokens`).
  final int contextTokens;

  /// Lo que se le deja a la respuesta: el `maxOutputTokens` del pedido.
  final int reservedOutputTokens;

  /// Lo que se le deja a la instrucción y al esquema.
  final int instructionTokens;

  /// Cuántos tokens de material entran de una vez; nunca menos que cero.
  int get inputTokens =>
      math.max(0, contextTokens - reservedOutputTokens - instructionTokens);

  /// Cuántos caracteres de material se mandan de una vez: lo que entra, con el
  /// tope de [kMaxCreationInputChars].
  int get inputChars =>
      math.min(kMaxCreationInputChars, inputTokens * kCreationCharsPerToken);

  /// De cuántos caracteres es cada parte cuando el material va por partes: lo
  /// que la app ya usa para leer un texto largo con este modelo
  /// (`textBudgetFor`), sin pasarse de lo que entra junto con la respuesta.
  /// Nunca menos de 500: una parte más chica no dice nada.
  int get partChars => math.max(
    500,
    math.min(textBudgetFor(contextTokens).partChars, inputChars),
  );

  @override
  bool operator ==(Object other) =>
      other is CreationBudget &&
      other.contextTokens == contextTokens &&
      other.reservedOutputTokens == reservedOutputTokens &&
      other.instructionTokens == instructionTokens;

  @override
  int get hashCode =>
      Object.hash(contextTokens, reservedOutputTokens, instructionTokens);

  @override
  String toString() =>
      'CreationBudget($contextTokens, salida $reservedOutputTokens)';
}

/// Qué se le da al modelo, en el orden del plan: el texto entero si cabe; si
/// no, las oraciones del resumen; si no, las de la síntesis; y si tampoco, por
/// partes —cada parte da su borrador y un último paso los une—.
enum CreationMaterialMode {
  fullText,
  summarySentences,
  synthesisSentences,
  byParts;

  /// Si va de una sola vez ([CreationMaterial.text]) y no por partes.
  bool get isSingle => this != byParts;
}

/// De qué texto salen las partes cuando el material va por partes: el más
/// corto que tengan las fuentes —la síntesis, el resumen o el texto entero—,
/// para leer de primera mano lo más posible con las mismas partes.
enum CreationPartsBase { fullText, summary, synthesis }

/// Un documento procesado en el material: cuánto aportó.
@immutable
class CreationMaterialSource {
  const CreationMaterialSource({
    required this.documentId,
    required this.title,
    required this.chars,
  });

  final String documentId;
  final String title;

  /// Cuántos caracteres suyos van en el material.
  final int chars;

  @override
  bool operator ==(Object other) =>
      other is CreationMaterialSource &&
      other.documentId == documentId &&
      other.title == title &&
      other.chars == chars;

  @override
  int get hashCode => Object.hash(documentId, title, chars);

  @override
  String toString() => 'CreationMaterialSource($documentId, $chars)';
}

/// Una parte del material por partes: su texto, con el título de su fuente
/// arriba, y de qué fuente es.
@immutable
class CreationMaterialPart {
  const CreationMaterialPart({
    required this.documentId,
    required this.text,
    required this.index,
  });

  final String documentId;

  /// El texto de la parte, con `## título` arriba.
  final String text;

  /// Su lugar entre TODAS las partes del texto, antes de elegir cuáles se
  /// leen: dos partes leídas con índices 3 y 9 dejaron cinco sin leer entre
  /// ellas.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is CreationMaterialPart &&
      other.documentId == documentId &&
      other.text == text &&
      other.index == index;

  @override
  int get hashCode => Object.hash(documentId, text, index);
}

/// El material de una creación (F43): lo que se le manda al modelo, ya armado
/// para que entre en su ventana (`CreationMaterialBuilder`).
///
/// Con un modo de una sola vez, [text] es todo lo que se manda, con cada
/// fuente bajo su título; con [CreationMaterialMode.byParts], [parts].
@immutable
class CreationMaterial {
  const CreationMaterial({
    required this.mode,
    required this.sources,
    this.text,
    this.parts = const [],
    this.partsBase,
    this.totalParts = 0,
    this.coverage = 1,
    this.withoutStudyMarks = const [],
    this.sourceStarts = const [],
  });

  final CreationMaterialMode mode;

  /// Lo que se manda de una vez; `null` por partes.
  final String? text;

  /// Las partes que se leen, en orden; vacías de una vez.
  final List<CreationMaterialPart> parts;

  /// De qué texto salen las partes; `null` de una vez.
  final CreationPartsBase? partsBase;

  /// En cuántas partes se cortó el texto, antes de elegir cuáles se leen
  /// ([kMaxCreationParts]).
  final int totalParts;

  /// Cuánto del texto elegido se lee de primera mano, de 0 a 1: menos de 1
  /// solo por partes, cuando había más de [kMaxCreationParts].
  final double coverage;

  /// Las fuentes que se usaron, en orden, con cuánto aportó cada una.
  final List<CreationMaterialSource> sources;

  /// Las fuentes vivas sin resumen ni síntesis todavía: analizarlas (F36) deja
  /// la próxima creación sobre lo esencial en vez de sobre partes sueltas.
  final List<String> withoutStudyMarks;

  /// De una vez, dónde empieza en [text] lo de cada una de [sources], en su
  /// orden (su `## título` incluido); vacía por partes, donde cada parte ya
  /// dice de qué fuente es. Con esto se sabe de qué documento es un pasaje
  /// que se encuentra en el material ([readings]).
  final List<int> sourceStarts;

  /// Lo que se leyó, cortado por fuente: de una vez, el tramo de [text] de
  /// cada una de [sources] (con [sourceStarts]); por partes, cada parte. Es lo
  /// que permite comprobar una cita contra el material y saber de qué
  /// documento es (el podcast, F47). Sin [sourceStarts] —un material armado a
  /// mano—, todo [text] es de la primera fuente si es la única, y de ninguna
  /// en particular si son varias.
  List<CreationMaterialReading> get readings {
    if (!mode.isSingle) {
      return [
        for (final part in parts)
          CreationMaterialReading(
            documentId: part.documentId,
            title: titles[part.documentId],
            text: part.text,
          ),
      ];
    }
    final all = text ?? '';
    if (sourceStarts.length != sources.length || sources.isEmpty) {
      final only = sources.length == 1 ? sources.single : null;
      return [
        CreationMaterialReading(
          documentId: only?.documentId,
          title: only?.title,
          text: all,
        ),
      ];
    }
    final readings = <CreationMaterialReading>[];
    for (final (i, source) in sources.indexed) {
      final from = sourceStarts[i].clamp(0, all.length);
      final next = i + 1 < sourceStarts.length
          ? sourceStarts[i + 1]
          : all.length;
      readings.add(
        CreationMaterialReading(
          documentId: source.documentId,
          title: source.title,
          text: all.substring(from, next.clamp(from, all.length)),
        ),
      );
    }
    return readings;
  }

  /// Cuántos caracteres se mandan, en total.
  int get chars =>
      text?.length ?? parts.fold(0, (sum, part) => sum + part.text.length);

  /// Cuántos tokens se estima que lee el modelo, sin la instrucción.
  int get estimatedInputTokens => estimateCreationTokens(chars);

  /// Si no hay nada que leer: ninguna fuente viva con texto.
  bool get isEmpty => sources.isEmpty || chars == 0;

  /// Los ids de las fuentes que de verdad se leyeron.
  List<String> get sourceIds => [for (final s in sources) s.documentId];

  /// Los títulos de las fuentes, por id.
  Map<String, String> get titles => {
    for (final s in sources) s.documentId: s.title,
  };

  @override
  String toString() =>
      'CreationMaterial(${mode.name}, $chars caracteres, '
      '${parts.length}/$totalParts partes)';
}

/// Un tramo de lo que se leyó en una creación, con su fuente:
/// [CreationMaterial.readings].
@immutable
class CreationMaterialReading {
  const CreationMaterialReading({
    required this.text,
    this.documentId,
    this.title,
  });

  /// El documento procesado del que es; `null` si no se sabe.
  final String? documentId;
  final String? title;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is CreationMaterialReading &&
      other.documentId == documentId &&
      other.title == title &&
      other.text == text;

  @override
  int get hashCode => Object.hash(documentId, title, text);
}
