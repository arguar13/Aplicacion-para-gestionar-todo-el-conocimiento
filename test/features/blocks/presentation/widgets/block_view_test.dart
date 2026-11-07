import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/features/blocks/presentation/widgets/block_view.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';

/// La nota de bloques de solo lectura: en el detalle, con la letra del tema;
/// en el lector (F46, paso 5j), con la de «Apariencia».
void main() {
  const blocks = [
    ContentBlock.heading(text: 'Título'),
    ContentBlock.heading(text: 'Subtítulo', level: 2),
    ContentBlock.paragraph(text: 'Un **párrafo**.'),
    ContentBlock.bulletItem(text: 'Una idea'),
    ContentBlock.checklistItem(text: 'Hecho', checked: true),
    ContentBlock.quote(text: 'Una cita'),
  ];

  Future<void> pump(WidgetTester tester, Widget view) => tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: view)),
      ),
    ),
  );

  /// El tamaño de la letra con que se ve [text].
  double? sizeOf(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(text),
      ),
    );
    // El tamaño del pedazo con [text], el más cercano hacia arriba que lo
    // diga: `Text.rich` envuelve los pedazos con la letra de siempre.
    double? sizeIn(InlineSpan span, double? inherited) {
      if (span is! TextSpan) return null;
      final size = span.style?.fontSize ?? inherited;
      if ((span.text ?? '').contains(text)) return size;
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (sizeIn(child, size) case final found?) return found;
      }
      return null;
    }

    return sizeIn(rich.text, null);
  }

  testWidgets('sin letra propia, la del tema, como siempre', (tester) async {
    await pump(tester, const BlockView(blocks: blocks));
    final theme = Theme.of(tester.element(find.byType(BlockView)));

    expect(sizeOf(tester, 'Título'), theme.textTheme.headlineSmall!.fontSize);
    expect(sizeOf(tester, 'Subtítulo'), theme.textTheme.titleLarge!.fontSize);
    expect(sizeOf(tester, 'párrafo'), theme.textTheme.bodyLarge!.fontSize);
  });

  testWidgets('con la letra del lector, los títulos salen de ella, más grandes '
      'y en negrita', (tester) async {
    const base = TextStyle(fontSize: 20, fontFamily: 'Lora');
    await pump(tester, const BlockView(blocks: blocks, baseStyle: base));

    expect(sizeOf(tester, 'Título'), 30);
    expect(sizeOf(tester, 'Subtítulo'), 27.5);
    expect(sizeOf(tester, 'párrafo'), 20);
    expect(sizeOf(tester, 'Una idea'), 20);
    expect(sizeOf(tester, 'Hecho'), 20);
    expect(sizeOf(tester, 'Una cita'), 20);
  });

  testWidgets('lo que suena se ve del color que se le pide', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readAloudHighlightProvider(
            BlockView.readAloudKey('rend', 0),
          ).overrideWithValue((0, 6)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BlockView(
              blocks: [ContentBlock.paragraph(text: 'Suena así.')],
              renditionId: 'rend',
              playingColor: Colors.green,
            ),
          ),
        ),
      ),
    );

    final colored = <String>[];
    tester
        .widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('Suena'),
          ),
        )
        .text
        .visitChildren((span) {
          if (span is TextSpan && span.style?.backgroundColor == Colors.green) {
            colored.add(span.text ?? '');
          }
          return true;
        });
    expect(colored.join(), 'Suena ');
  });

  test('lo que lee el lector: un texto por bloque, con su nombre y en '
      'Markdown', () {
    expect(
      BlockView.readAloudParts('rend', const [
        ContentBlock.heading(text: 'Título'),
        ContentBlock.paragraph(text: 'Un **párrafo**.'),
      ]),
      [
        (
          sourceKey: 'blocks:rend:0',
          text: 'Título',
          markdown: true,
          transcript: false,
        ),
        (
          sourceKey: 'blocks:rend:1',
          text: 'Un **párrafo**.',
          markdown: true,
          transcript: false,
        ),
      ],
    );
  });
}
