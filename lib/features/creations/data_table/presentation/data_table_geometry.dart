import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';

/// Las letras de la tabla en un tema.
@immutable
class DataTableStyles {
  const DataTableStyles({
    required this.header,
    required this.cell,
    required this.firstCell,
    required this.textScaler,
    required this.textDirection,
  });

  factory DataTableStyles.of(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cell = text.bodyMedium!;
    return DataTableStyles(
      header: text.labelLarge!.copyWith(fontWeight: FontWeight.w700),
      cell: cell,
      firstCell: cell.copyWith(fontWeight: FontWeight.w600),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    );
  }

  final TextStyle header;
  final TextStyle cell;
  final TextStyle firstCell;
  final TextScaler textScaler;
  final TextDirection textDirection;

  /// La letra de la celda de [column]: la primera, más marcada; las de
  /// números, con cifras de ancho fijo para que se encolumnen.
  TextStyle cellAt(int column, {required bool numeric}) {
    final base = column == 0 ? firstCell : cell;
    return numeric
        ? base.copyWith(fontFeatures: const [FontFeature.tabularFigures()])
        : base;
  }

  @override
  bool operator ==(Object other) =>
      other is DataTableStyles &&
      other.header == header &&
      other.cell == cell &&
      other.firstCell == firstCell &&
      other.textScaler == textScaler &&
      other.textDirection == textDirection;

  @override
  int get hashCode =>
      Object.hash(header, cell, firstCell, textScaler, textDirection);
}

/// Las medidas de una tabla en una pantalla (F43): el ancho de cada columna,
/// el alto de cada fila y qué celdas no entran enteras —esas se abren al
/// tocarlas—. Se mide con la misma letra con que se dibuja, así lo medido y
/// lo dibujado coinciden.
///
/// - Cada columna, del ancho de su valor más largo en un renglón, entre
///   [minColumnWidth] y [maxColumnWidth]; la primera —la fija—, nunca más
///   que [maxFirstShare] del ancho de la pantalla, para que siempre quede
///   lugar para desplazar las demás.
/// - Si todas juntas no llegan al ancho, se ensanchan parejo hasta llenarlo.
/// - Cada fila, del alto de su celda más alta, con hasta [maxLines]
///   renglones por celda.
@immutable
class DataTableGeometry {
  const DataTableGeometry({
    required this.widths,
    required this.headerHeight,
    required this.heights,
    required this.truncated,
  });

  factory DataTableGeometry.measure(
    StudyTable table,
    DataTableStyles styles, {
    required double available,
  }) {
    final columns = table.columns.length;
    final natural = List<double>.filled(columns, 0);
    for (var c = 0; c < columns; c++) {
      final column = table.columns[c];
      var widest = _lineWidth(column.name, styles.header, styles) + sortSpace;
      for (final row in table.rows) {
        widest = math.max(
          widest,
          _lineWidth(
            row[c],
            styles.cellAt(c, numeric: column.isNumeric),
            styles,
          ),
        );
      }
      natural[c] = widest + horizontalPadding * 2;
    }
    final firstMax = math.max(
      minColumnWidth,
      math.min(maxColumnWidth, available * maxFirstShare),
    );
    final widths = [
      for (var c = 0; c < columns; c++)
        natural[c].clamp(minColumnWidth, c == 0 ? firstMax : maxColumnWidth),
    ];
    final total = widths.fold<double>(0, (sum, w) => sum + w);
    if (total < available && total > 0) {
      final grow = available / total;
      for (var c = 0; c < columns; c++) {
        widths[c] = (widths[c] * grow).floorToDouble();
      }
    }

    var headerHeight = minHeaderHeight;
    for (var c = 0; c < columns; c++) {
      final painter = _painter(
        table.columns[c].name,
        styles.header,
        styles,
        maxLines: 2,
      )..layout(maxWidth: widths[c] - horizontalPadding * 2 - sortSpace);
      headerHeight = math.max(
        headerHeight,
        painter.height.ceilToDouble() + verticalPadding * 2,
      );
      painter.dispose();
    }

    final heights = <double>[];
    final truncated = <List<bool>>[];
    for (final row in table.rows) {
      var height = minRowHeight;
      final cut = List<bool>.filled(columns, false);
      for (var c = 0; c < columns; c++) {
        if (row[c].isEmpty) continue;
        final painter = _painter(
          row[c],
          styles.cellAt(c, numeric: table.columns[c].isNumeric),
          styles,
          maxLines: maxLines,
        )..layout(maxWidth: widths[c] - horizontalPadding * 2);
        height = math.max(
          height,
          painter.height.ceilToDouble() + verticalPadding * 2,
        );
        cut[c] = painter.didExceedMaxLines;
        painter.dispose();
      }
      heights.add(height);
      truncated.add(cut);
    }
    return DataTableGeometry(
      widths: widths,
      headerHeight: headerHeight,
      heights: heights,
      truncated: truncated,
    );
  }

  static const double minColumnWidth = 88;
  static const double maxColumnWidth = 280;
  static const double maxFirstShare = 0.45;
  static const double horizontalPadding = 14;
  static const double verticalPadding = 12;
  static const double minRowHeight = 48;
  static const double minHeaderHeight = 52;
  static const int maxLines = 3;

  /// El lugar de la flecha de orden junto al nombre de la columna.
  static const double sortSpace = 22;

  /// Lo que se mide de una celda para su ancho: un valor más largo que esto
  /// ya ocupa el ancho máximo de la columna.
  static const int _measuredChars = 160;

  final List<double> widths;
  final double headerHeight;
  final List<double> heights;

  /// Por fila y columna (en el orden de la IA), si la celda no entra entera.
  final List<List<bool>> truncated;

  double get firstWidth => widths.isEmpty ? 0 : widths.first;

  /// El ancho de las columnas que se desplazan.
  double get restWidth =>
      widths.skip(1).fold<double>(0, (sum, width) => sum + width);

  static double _lineWidth(
    String text,
    TextStyle style,
    DataTableStyles styles,
  ) {
    if (text.isEmpty) return 0;
    final clipped = text.length > _measuredChars
        ? text.substring(0, _measuredChars)
        : text;
    final painter = _painter(
      clipped.replaceAll('\n', ' '),
      style,
      styles,
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  static TextPainter _painter(
    String text,
    TextStyle style,
    DataTableStyles styles, {
    required int maxLines,
  }) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: styles.textDirection,
    textScaler: styles.textScaler,
    maxLines: maxLines,
    ellipsis: '…',
  );
}
