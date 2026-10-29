import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';

/// Las letras de lo creado (F43): cada familia que usa un par está
/// empaquetada en pubspec.yaml, con todos los pesos que se le piden, y cada
/// archivo tiene su licencia OFL al lado.
void main() {
  /// Las familias de pubspec.yaml con sus pesos y estilos.
  Map<String, Set<String>> declared() {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final families = <String, Set<String>>{};
    String? family;
    String? weight;
    for (final line in lines) {
      final familyMatch = RegExp(r'^\s+- family: (.+)$').firstMatch(line);
      if (familyMatch != null) {
        family = familyMatch.group(1)!.trim();
        families[family] = {};
        continue;
      }
      final weightMatch = RegExp(r'^\s+weight: (\d+)$').firstMatch(line);
      if (weightMatch != null && family != null) {
        weight = weightMatch.group(1);
        families[family]!.add(weight!);
        continue;
      }
      if (RegExp(r'^\s+style: italic$').hasMatch(line) && family != null) {
        families[family]!.add('$weight italic');
      }
    }
    return families;
  }

  /// Los archivos de pubspec.yaml de cada familia.
  Map<String, Set<String>> assets() {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final out = <String, Set<String>>{};
    String? family;
    for (final line in lines) {
      final familyMatch = RegExp(r'^\s+- family: (.+)$').firstMatch(line);
      if (familyMatch != null) {
        family = familyMatch.group(1)!.trim();
        out[family] = {};
      }
      final asset = RegExp(r'^\s+- asset: (.+)$').firstMatch(line);
      if (asset != null && family != null) out[family]!.add(asset.group(1)!);
    }
    return out;
  }

  test('cada familia de cada par está en pubspec.yaml con todos sus pesos', () {
    final families = declared();
    for (final entry in CreationFontPair.declaredWeights.entries) {
      expect(
        families[entry.key],
        isNotNull,
        reason: '${entry.key} no está en pubspec.yaml',
      );
      for (final weight in entry.value) {
        expect(
          families[entry.key],
          contains('$weight'),
          reason: '${entry.key} no declara el peso $weight',
        );
      }
    }
    for (final family in CreationFontPair.italicFamilies) {
      expect(
        families[family]!.where((w) => w.endsWith('italic')),
        isNotEmpty,
        reason: '$family no declara su itálica',
      );
    }
    for (final pair in CreationFontPair.values) {
      for (final family in [pair.display, pair.body, pair.figures]) {
        expect(CreationFontPair.declaredWeights, contains(family));
      }
      expect(
        CreationFontPair.declaredWeights[pair.display],
        contains(pair.displayWeight),
      );
      if (pair.displayItalic) {
        expect(CreationFontPair.italicFamilies, contains(pair.display));
      }
    }
  });

  test('la familia «Inter» de la app no cambia: sigue con sus dos pesos', () {
    // Declararle más pesos cambiaría la negrita de toda la app; para lo
    // creado está «Inter Creation», el mismo archivo.
    expect(declared()['Inter'], {'400', '500'});
  });

  test('cada archivo existe y tiene su licencia OFL al lado', () {
    final all = assets();
    final files = <String>{
      for (final family in CreationFontPair.declaredWeights.keys)
        ...all[family]!,
    };
    expect(files, isNotEmpty);
    for (final path in files) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path no existe');
      expect(file.lengthSync(), greaterThan(50000), reason: '$path vacío');
    }
    final licenses = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('-OFL.txt'))
        .toList();
    expect(licenses, hasLength(7));
    for (final license in licenses) {
      expect(
        license.readAsStringSync(),
        contains('SIL OPEN FONT LICENSE Version 1.1'),
      );
    }
    for (final path in files.where((p) => !p.contains('InterVariable'))) {
      final name = path.split('/').last.split('-').first;
      expect(
        File('assets/fonts/$name-OFL.txt').existsSync(),
        isTrue,
        reason: 'falta la licencia de $path',
      );
    }
  });

  test('lo nuevo pesa menos de 3 MB', () {
    final added = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('-Variable.ttf'))
        .fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(added, lessThan(3 * 1024 * 1024));
  });

  test('el peso pedido se lleva al declarado más cercano', () {
    expect(CreationFontPair.nearestDeclaredWeight('Nunito', 700), 800);
    expect(CreationFontPair.nearestDeclaredWeight('Nunito', 500), 600);
    expect(CreationFontPair.nearestDeclaredWeight('Lora', 500), 500);
    expect(CreationFontPair.nearestDeclaredWeight('Caveat', 100), 400);
    expect(CreationFontPair.nearestDeclaredWeight('Desconocida', 650), 650);
  });

  test('el estilo pide el peso a la cara y al eje variable a la vez', () {
    final style = CreationFontPair.technical.displayStyle(
      size: 80,
      color: const Color(0xFF000000),
    );
    expect(style.fontFamily, 'Space Grotesk');
    expect(style.fontWeight, FontWeight.w700);
    expect(style.fontVariations, [const FontVariation('wght', 700)]);
    expect(style.letterSpacing, closeTo(-0.02 * 80, 1e-9));
  });

  test('la manuscrita se agranda y no se inventa una itálica', () {
    final style = CreationFontPair.handwritten.displayStyle(
      size: 100,
      color: const Color(0xFF000000),
      italic: true,
    );
    expect(style.fontSize, closeTo(128, 1e-9));
    expect(style.fontStyle, FontStyle.normal);
    final editorial = CreationFontPair.editorial.displayStyle(
      size: 100,
      color: const Color(0xFF000000),
      italic: true,
    );
    expect(editorial.fontStyle, FontStyle.italic);
  });

  test('las cifras del par técnico van en la monoespaciada', () {
    expect(
      CreationFontPair.technical
          .figuresStyle(size: 40, color: const Color(0xFF000000))
          .fontFamily,
      'JetBrains Mono',
    );
  });

  test('fromName', () {
    expect(CreationFontPair.fromName('book'), CreationFontPair.book);
    expect(CreationFontPair.fromName(null), isNull);
    expect(CreationFontPair.fromName('futura'), isNull);
  });
}
