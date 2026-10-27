import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que hace la persona en el chat (F42), dicho una sola vez para todas las
/// pruebas que lo usan: escribir y mandar con el botón redondo, elegir dónde
/// se pregunta y lo que vive en la hoja «Agregar al chat» del «+».
final _es = AppLocalizationsEs();

/// Escribe [text] en el campo y lo manda con el botón, sin esperar.
Future<void> typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat-composer-field')), text);
  await tester.pump();
  await tester.tap(find.byTooltip(_es.chatSendTooltip));
}

/// Escribe [text], lo manda y espera a que todo se asiente.
Future<void> sendChatMessage(WidgetTester tester, String text) async {
  await typeAndSend(tester, text);
  await tester.pumpAndSettle();
}

/// Abre «Agregar al chat».
Future<void> openAddToChat(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_es.chatAddTooltip));
  await tester.pumpAndSettle();
}

/// Cierra las hojas que queden abiertas, de arriba hacia abajo, tocando el
/// fondo como lo haría la persona.
Future<void> closeChatSheets(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    if (find.byType(BottomSheet).evaluate().isEmpty) return;
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  }
}

/// Elige [label] —un modo («Con mi bóveda», «Conversación libre») o un
/// cuaderno («Toda la bóveda», su nombre)— en la hoja «Dónde pregunto». Se
/// llega por la línea debajo del modelo o, con [fromAddSheet], por la fila
/// del «+»: es la misma hoja. Después cierra lo que quede abierto.
Future<void> chooseChatScope(
  WidgetTester tester,
  String label, {
  bool fromAddSheet = false,
}) async {
  if (fromAddSheet) {
    await openAddToChat(tester);
    await tester.tap(find.byKey(const Key('chat-add-scope')));
  } else {
    await tester.tap(find.byKey(const Key('chat-scope-line')));
  }
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(of: find.byType(BottomSheet), matching: find.text(label))
        .last,
  );
  await tester.pumpAndSettle();
  await closeChatSheets(tester);
}

/// Pasa a «Con mi bóveda» ([on]) o a la conversación libre.
Future<void> setVaultMode(
  WidgetTester tester, {
  required bool on,
  bool fromAddSheet = false,
}) => chooseChatScope(
  tester,
  on ? _es.chatModeVault : _es.chatModeFree,
  fromAddSheet: fromAddSheet,
);

/// Adjunta desde la tarjeta [card] de «Agregar al chat»: `chat-add-camera`,
/// `chat-add-photos` o `chat-add-files`.
Future<void> attachFrom(WidgetTester tester, String card) async {
  await openAddToChat(tester);
  await tester.tap(find.byKey(Key(card)));
  await tester.pumpAndSettle();
}
