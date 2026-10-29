import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las familias de lo creado con sus archivos, como en pubspec.yaml.
const creationFontFiles = {
  'Inter Creation': ['InterVariable.ttf'],
  'Playfair Display': [
    'PlayfairDisplay-Variable.ttf',
    'PlayfairDisplay-Italic-Variable.ttf',
  ],
  'Lora': ['Lora-Variable.ttf', 'Lora-Italic-Variable.ttf'],
  'Source Sans 3': ['SourceSans3-Variable.ttf'],
  'Space Grotesk': ['SpaceGrotesk-Variable.ttf'],
  'Nunito': ['Nunito-Variable.ttf'],
  'Caveat': ['Caveat-Variable.ttf'],
  'JetBrains Mono': ['JetBrainsMono-Variable.ttf'],
};

/// Carga las letras de verdad de lo creado: la de las pruebas dibuja cada
/// letra como un cuadrado de 1 em, que mide casi el doble que una real. Con
/// esto el ajuste del texto se prueba con las medidas que va a tener en el
/// teléfono.
Future<void> loadCreationFonts() async {
  for (final MapEntry(key: family, value: files) in creationFontFiles.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
}

/// Los problemas de texto de todo lo que está debajo de [root]: un texto que
/// se dibuja recortado (su alto real es mayor que el lugar que tiene), o que
/// se sale de [root]. Vacío si está todo bien.
List<String> textProblems(
  WidgetTester tester,
  Finder root, {
  double tolerance = 2,
  bool allowEllipsis = true,
}) {
  final problems = <String>[];
  final rootBox = tester.renderObject<RenderBox>(root);
  final rootRect = rootBox.localToGlobal(Offset.zero) & rootBox.size;
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: root, matching: find.byType(RichText)),
  )) {
    final text = paragraph.text.toPlainText();
    if (text.trim().isEmpty) continue;
    final label = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    final dry = paragraph.getDryLayout(
      BoxConstraints(maxWidth: paragraph.size.width),
    );
    if (dry.height > paragraph.size.height + 0.5) {
      problems.add(
        'recortado: «$label» (${dry.height} > ${paragraph.size.height})',
      );
    }
    if (!allowEllipsis && paragraph.didExceedMaxLines) {
      problems.add('cortado con «…»: «$label»');
    }
    final topLeft = paragraph.localToGlobal(Offset.zero);
    final bottomRight = paragraph.localToGlobal(
      paragraph.size.bottomRight(Offset.zero),
    );
    final rect = Rect.fromPoints(topLeft, bottomRight);
    if (rect.left < rootRect.left - tolerance ||
        rect.top < rootRect.top - tolerance ||
        rect.right > rootRect.right + tolerance ||
        rect.bottom > rootRect.bottom + tolerance) {
      problems.add('fuera del lienzo: «$label» $rect en $rootRect');
    }
  }
  return problems;
}

/// Guarda como PNG lo que se dibuja en [boundary], si la variable de
/// entorno MUESTRARIO_PNG dice en qué carpeta (para mirar el muestrario a
/// ojo; en la suite no se usa).
Future<void> maybeDumpPng(
  WidgetTester tester,
  Finder boundary,
  String name, {
  double pixelRatio = 1,
}) async {
  final dir = Platform.environment['MUESTRARIO_PNG'];
  if (dir == null || dir.isEmpty) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(boundary);
    final image = await render.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}
