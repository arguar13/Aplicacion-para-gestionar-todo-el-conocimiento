import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Termina la hoja «¿Qué va a Procesado?» (F41) llevando el texto extraído
/// entero: lo mínimo para que triar arme un documento procesado y deje la
/// fuente triada. La hoja tiene que estar abierta.
Future<void> finishTriageWithText(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('triage-switch-text')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('triage-done')));
  await tester.pumpAndSettle();
}

/// Si la hoja «¿Qué va a Procesado?» está abierta.
Finder get triageSheet => find.byKey(const Key('processed-triage-sheet'));
