import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que hace la persona en el chat (F42), dicho una sola vez para todas las
/// pruebas que lo usan: escribir y mandar con el botón redondo, elegir dónde
/// se pregunta y lo que vive en la hoja «Agregar al chat» del «+».
///
/// Cada toque llega de verdad a lo que dice tocar ([tapAsUser]): si una hoja
/// que no se cerró, un aviso o el borde de la pantalla lo tapan, la prueba
/// falla en vez de tocar al lado y seguir como si nada.
final _es = AppLocalizationsEs();

/// Toca [finder] como lo haría la persona: si está en algo que se desplaza y
/// no se ve entero, lo desplaza lo justo para verlo —lo que ya se ve no se
/// mueve—, y exige que el toque, en su centro, le llegue a él y no a lo que
/// tenga encima.
Future<void> tapAsUser(WidgetTester tester, Finder finder) async {
  final element = tester.element(finder);
  for (final policy in const [
    ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ScrollPositionAlignmentPolicy.keepVisibleAtStart,
  ]) {
    await Scrollable.ensureVisible(element, alignmentPolicy: policy);
  }
  await tester.pump();
  final target = tester.renderObject(finder);
  final center = tester.getCenter(finder);
  final hit = tester.hitTestOnBinding(center);
  expect(
    hit.path.any((entry) => identical(entry.target, target)),
    isTrue,
    reason:
        'El toque en $center no le llega a $finder: algo lo tapa —le llega '
        'primero a ${hit.path.first.target}—.',
  );
  await tester.tap(finder);
}

/// Escribe [text] en el campo y lo manda con el botón, sin esperar.
///
/// El botón tiene que estar prendido y recibir el toque, y lo mandado sale
/// del campo en el acto: si el toque no llegó, falla acá.
Future<void> typeAndSend(WidgetTester tester, String text) async {
  final field = find.byKey(const Key('chat-composer-field'));
  await tester.enterText(field, text);
  await tester.pump();
  final send = find.byTooltip(_es.chatSendTooltip);
  expect(
    tester
        .widget<IconButton>(
          find.ancestor(of: send, matching: find.byType(IconButton)),
        )
        .onPressed,
    isNotNull,
    reason: 'Con «$text» escrito, enviar tiene que estar prendido.',
  );
  await tapAsUser(tester, send);
  expect(
    tester.widget<TextField>(field).controller!.text,
    isEmpty,
    reason: '«$text» no salió del campo: el botón de enviar no mandó.',
  );
}

/// Escribe [text], lo manda y espera a que todo se asiente.
Future<void> sendChatMessage(WidgetTester tester, String text) async {
  await typeAndSend(tester, text);
  await tester.pumpAndSettle();
}

/// Abre «Agregar al chat».
Future<void> openAddToChat(WidgetTester tester) async {
  await tapAsUser(tester, find.byTooltip(_es.chatAddTooltip));
  await tester.pumpAndSettle();
}

/// Cierra las hojas que queden abiertas, de arriba hacia abajo, tocando el
/// fondo —arriba de todo— como lo haría la persona. Una hoja que no deja
/// fondo a la vista no se puede cerrar así: la prueba falla.
Future<void> closeChatSheets(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    if (find.byType(BottomSheet).evaluate().isEmpty) return;
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  }
  expect(
    find.byType(BottomSheet),
    findsNothing,
    reason:
        'Tocar arriba de todo no cerró la hoja: no deja el fondo a la vista.',
  );
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
    await tapAsUser(tester, find.byKey(const Key('chat-add-scope')));
  } else {
    await tapAsUser(tester, find.byKey(const Key('chat-scope-line')));
  }
  await tester.pumpAndSettle();
  await tapAsUser(
    tester,
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
  await tapAsUser(tester, find.byKey(Key(card)));
  await tester.pumpAndSettle();
}
