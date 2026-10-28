import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';

/// El vacío de cualquier pantalla: su acción, su segundo camino (F41) y la
/// entrada, que respeta «sin animaciones».
void main() {
  Widget host({required bool still, Widget? secondary}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Scaffold(
        body: EmptyStateView(
          icon: Icons.inbox_outlined,
          title: 'Nada todavía',
          actionLabel: 'Ir',
          onAction: () {},
          secondary: secondary,
        ),
      ),
    ),
  );

  double opacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.ancestor(
          of: find.text('Nada todavía'),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  testWidgets('entra con una animación breve', (tester) async {
    await tester.pumpWidget(host(still: false));

    expect(opacity(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
  });

  testWidgets('con «sin animaciones» aparece de una', (tester) async {
    await tester.pumpWidget(host(still: true));
    await tester.pump();

    expect(opacity(tester), 1);
  });

  testWidgets('el segundo camino va debajo de la acción', (tester) async {
    await tester.pumpWidget(
      host(still: true, secondary: const Text('Otro camino')),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Otro camino')).dy,
      greaterThan(tester.getTopLeft(find.text('Ir')).dy),
    );
  });
}
