import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que el usuario fue escribiendo y eligiendo para una fecha histórica, y
/// la [HistoricalDate] que resulta.
///
/// Vive aparte del formulario para que quien lo aloja lo conserve aunque el
/// formulario desaparezca y vuelva —el diálogo de propiedades lo muestra solo
/// mientras la categoría escrita es de tipo fecha—, y para que lea el
/// resultado al confirmar sin que el formulario le avise con callbacks.
class HistoricalDateController extends ChangeNotifier {
  HistoricalDateController() {
    yearController.addListener(notifyListeners);
    dayController.addListener(notifyListeners);
  }

  final yearController = TextEditingController();
  final dayController = TextEditingController(text: '1');

  bool _isBce = false;
  DatePrecision _precision = DatePrecision.year;
  int _month = 1;
  bool _isCirca = false;

  bool get isBce => _isBce;
  set isBce(bool value) {
    if (value == _isBce) return;
    _isBce = value;
    notifyListeners();
  }

  DatePrecision get precision => _precision;
  set precision(DatePrecision value) {
    if (value == _precision) return;
    _precision = value;
    notifyListeners();
  }

  /// De 1 a 12.
  int get month => _month;
  set month(int value) {
    if (value == _month) return;
    _month = value;
    notifyListeners();
  }

  bool get isCirca => _isCirca;
  set isCirca(bool value) {
    if (value == _isCirca) return;
    _isCirca = value;
    notifyListeners();
  }

  /// El año escrito, o `null` si falta o no es válido. Los años empiezan en
  /// 1: el calendario no tiene año cero (1 a.C. es seguido por 1 d.C.).
  int? get year {
    final parsed = int.tryParse(yearController.text.trim());
    return parsed != null && parsed >= 1 ? parsed : null;
  }

  /// `true` si hay algo escrito en el año y no sirve. Un campo vacío todavía
  /// no es un error: nadie escribió nada.
  bool get hasYearError =>
      yearController.text.trim().isNotEmpty && year == null;

  /// Si la precisión elegida usa el mes.
  bool get usesMonth =>
      _precision == DatePrecision.day || _precision == DatePrecision.month;

  /// Si la precisión elegida usa el día.
  bool get usesDay => _precision == DatePrecision.day;

  /// Cuántos días tiene el mes elegido en el año escrito —29 en febrero de un
  /// año bisiesto—. Con el año todavía sin escribir, el de un año común.
  int get maxDay {
    final astronomical = HistoricalDate(
      year: year ?? 1,
      precision: DatePrecision.year,
      isBce: _isBce,
    ).astronomicalYear;
    return daysInMonth(astronomical, _month);
  }

  int? get _day => int.tryParse(dayController.text.trim());

  bool get _dayInRange {
    final day = _day;
    return day != null && day >= 1 && day <= maxDay;
  }

  /// `true` si hay algo escrito en el día y ese día no existe en el mes.
  bool get hasDayError =>
      usesDay && dayController.text.trim().isNotEmpty && !_dayInRange;

  /// La fecha completa, o `null` mientras falte algo o algo no sea válido.
  HistoricalDate? get date {
    final year = this.year;
    if (year == null) return null;
    if (usesDay && !_dayInRange) return null;

    return HistoricalDate(
      year: year,
      precision: _precision,
      month: usesMonth ? _month : null,
      day: usesDay ? _day : null,
      isBce: _isBce,
      isCirca: _isCirca,
    );
  }

  @override
  void dispose() {
    yearController.dispose();
    dayController.dispose();
    super.dispose();
  }
}

/// El formulario de una fecha histórica: año con su era, precisión, mes y día
/// según la precisión, y si es aproximada.
///
/// Escribe en un [HistoricalDateController]; quien lo aloja lo crea, lo lee y
/// lo descarta.
class HistoricalDateForm extends StatelessWidget {
  const HistoricalDateForm({required this.controller, super.key});

  final HistoricalDateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _Fields(controller: controller),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.controller});

  final HistoricalDateController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final precision = controller.precision;
    final date = controller.date;

    final periodHint = switch (precision) {
      DatePrecision.decade => l10n.datePickerPeriodHintDecade,
      DatePrecision.century => l10n.datePickerPeriodHintCentury,
      _ => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller.yearController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: InputDecoration(
                  labelText: l10n.datePickerYear,
                  errorText: controller.hasYearError
                      ? l10n.datePickerYearInvalid
                      : null,
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.datePickerEraCe),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.datePickerEraBce),
                  ),
                ],
                selected: {controller.isBce},
                onSelectionChanged: (selection) =>
                    controller.isBce = selection.single,
              ),
            ),
          ],
        ),
        if (periodHint != null) ...[
          const SizedBox(height: 4),
          Text(
            periodHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          l10n.datePickerPrecision,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in DatePrecision.values)
              ChoiceChip(
                label: Text(_precisionLabel(l10n, option)),
                selected: precision == option,
                onSelected: (_) => controller.precision = option,
              ),
          ],
        ),
        if (controller.usesMonth) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(labelText: l10n.datePickerMonth),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      isDense: true,
                      value: controller.month,
                      items: [
                        for (var month = 1; month <= 12; month++)
                          DropdownMenuItem(
                            value: month,
                            child: Text(_monthName(locale, month)),
                          ),
                      ],
                      onChanged: (month) {
                        if (month != null) controller.month = month;
                      },
                    ),
                  ),
                ),
              ),
              if (controller.usesDay) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: controller.dayController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.datePickerDay,
                      errorText: controller.hasDayError
                          ? l10n.datePickerDayInvalid(controller.maxDay)
                          : null,
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: controller.isCirca,
          title: Text(l10n.datePickerCirca),
          onChanged: (value) => controller.isCirca = value ?? false,
        ),
        if (date != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.datePickerPreview(date.label),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

String _precisionLabel(AppLocalizations l10n, DatePrecision precision) {
  return switch (precision) {
    DatePrecision.day => l10n.datePickerPrecisionDay,
    DatePrecision.month => l10n.datePickerPrecisionMonth,
    DatePrecision.year => l10n.datePickerPrecisionYear,
    DatePrecision.decade => l10n.datePickerPrecisionDecade,
    DatePrecision.century => l10n.datePickerPrecisionCentury,
  };
}

/// El nombre del mes en el idioma de la app. Se formatea un año cualquiera
/// (2000): solo importa el mes, y `DateFormat` no sabe de años a.C.
String _monthName(String locale, int month) {
  final name = DateFormat.MMMM(locale).format(DateTime(2000, month));
  return toBeginningOfSentenceCase(name, locale) ?? name;
}
