import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_icon_names.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';

/// El juego de íconos de lo creado (F43): la IA los elige por nombre.
void main() {
  test('los nombres que se le dan a la IA son los del juego, en orden', () {
    expect(CreationIcons.byKey.keys.toList(), creationIconNames);
    expect(CreationIcons.keys, creationIconNames);
    expect(creationIconNames.length, greaterThanOrEqualTo(80));
    expect(creationIconNames.toSet(), hasLength(creationIconNames.length));
    for (final name in creationIconNames) {
      expect(name, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
    }
  });

  test('un nombre se entiende con mayúsculas, espacios, guiones y tildes', () {
    expect(CreationIcons.normalize('Balance'), 'balance');
    expect(CreationIcons.normalize(' trending up '), 'trending_up');
    expect(CreationIcons.normalize('trending-up'), 'trending_up');
    expect(CreationIcons.normalize('Música'), 'music');
    expect(CreationIcons.normalize('justicia'), 'balance');
    expect(CreationIcons.normalize('lightbulb_outline'), 'lightbulb');
  });

  test('un nombre desconocido da el de reserva, sin fallar', () {
    expect(CreationIcons.normalize('unicornio'), isNull);
    expect(CreationIcons.normalize(null), isNull);
    expect(CreationIcons.resolve('unicornio'), CreationIcons.fallback);
    expect(CreationIcons.resolve(null), CreationIcons.fallback);
    expect(CreationIcons.resolve('gavel'), Icons.gavel);
  });

  test('cada alias apunta a un ícono del juego', () {
    for (final raw in ['idea', 'mundo', 'dinero', 'cita', 'extension']) {
      expect(CreationIcons.byKey, contains(CreationIcons.normalize(raw)));
    }
  });
}
