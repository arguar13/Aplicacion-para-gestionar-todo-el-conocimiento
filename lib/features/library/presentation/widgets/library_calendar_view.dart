import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Sobre qué fecha se arma el calendario (F16, D7).
enum CalendarAxis {
  /// Cuándo ocurrió lo que cuenta el elemento. El eje por defecto: es lo
  /// que el encargo nombra primero, y responde «qué pasó cuándo» en vez de
  /// «qué guardé cuándo».
  eventDate,

  /// Cuándo se guardó.
  capturedAt,
}

/// La biblioteca como un calendario, mes a mes (F16, D7).
///
/// Reusa `LibraryQuery` —el mismo filtro que la lista— y, para «Fecha del
/// hecho», `timelineEventsProvider` (F12): no hay un segundo motor de
/// fechas. Un hecho sin precisión de día —«siglo V», «1920»— no tiene una
/// sola celda donde ir, así que no aparece acá; sigue viéndose entero en
/// la línea de tiempo.
class LibraryCalendarView extends ConsumerStatefulWidget {
  const LibraryCalendarView({required this.items, super.key});

  final List<KnowledgeItem> items;

  @override
  ConsumerState<LibraryCalendarView> createState() =>
      _LibraryCalendarViewState();
}

class _LibraryCalendarViewState extends ConsumerState<LibraryCalendarView> {
  var _axis = CalendarAxis.eventDate;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    _month = DateTime(now.year, now.month);
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  /// Los elementos de cada día del mes en pantalla, según el eje elegido.
  Map<int, List<KnowledgeItem>> _byDay(List<TimelineEvent>? events) {
    final byId = {for (final item in widget.items) item.id: item};
    final result = <int, List<KnowledgeItem>>{};

    void add(int day, KnowledgeItem item) =>
        result.putIfAbsent(day, () => []).add(item);

    if (_axis == CalendarAxis.capturedAt) {
      for (final item in widget.items) {
        final captured = item.source.capturedAt;
        if (captured.year == _month.year && captured.month == _month.month) {
          add(captured.day, item);
        }
      }
      return result;
    }

    for (final event in events ?? const <TimelineEvent>[]) {
      if (event.date.precision != DatePrecision.day) continue;
      if (event.date.astronomicalYear != _month.year ||
          event.date.month != _month.month) {
        continue;
      }
      final item = byId[event.itemId];
      if (item != null) add(event.date.day!, item);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final query = ref.watch(libraryQueryNotifierProvider);
    final events = _axis == CalendarAxis.eventDate
        ? ref.watch(timelineEventsProvider(query)).valueOrNull
        : null;
    final byDay = _byDay(events);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.libraryCalendarPreviousMonth,
                onPressed: () => _changeMonth(-1),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(locale).format(_month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.libraryCalendarNextMonth,
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SegmentedButton<CalendarAxis>(
            segments: [
              ButtonSegment(
                value: CalendarAxis.eventDate,
                label: Text(l10n.libraryCalendarAxisEventDate),
              ),
              ButtonSegment(
                value: CalendarAxis.capturedAt,
                label: Text(l10n.libraryCalendarAxisCapturedAt),
              ),
            ],
            selected: {_axis},
            onSelectionChanged: (selected) =>
                setState(() => _axis = selected.first),
          ),
        ),
        const SizedBox(height: 8),
        _WeekdayHeader(locale: locale),
        Expanded(
          child: _MonthGrid(
            month: _month,
            byDay: byDay,
            onTapDay: (day, dayItems) =>
                _showDayItems(context, day: day, items: dayItems),
          ),
        ),
      ],
    );
  }

  void _showDayItems(
    BuildContext context, {
    required int day,
    required List<KnowledgeItem> items,
  }) {
    final locale = Localizations.localeOf(context).toString();
    final date = DateTime(_month.year, _month.month, day);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(DateFormat.yMMMMd(locale).format(date)),
              dense: true,
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items)
                    ListTile(
                      title: Text(item.title),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('${RoutePaths.library}/${item.id}');
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.locale});

  final String locale;

  @override
  Widget build(BuildContext context) {
    // Lunes primero: `DateTime.monday` es 1, y así son los siete días de
    // cualquier semana ISO, sea cual sea el idioma.
    final base = DateTime(2026, 9, 21); // un lunes, para anclar el orden.
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                DateFormat.E(locale).format(base.add(Duration(days: i))),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.byDay,
    required this.onTapDay,
  });

  final DateTime month;
  final Map<int, List<KnowledgeItem>> byDay;
  final void Function(int day, List<KnowledgeItem> items) onTapDay;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 1 (lunes) a 7 (domingo): cuántas celdas vacías van antes del día 1.
    final leadingBlanks = DateTime(month.year, month.month).weekday - 1;
    final theme = Theme.of(context);

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      itemCount: leadingBlanks + daysInMonth,
      itemBuilder: (context, index) {
        if (index < leadingBlanks) return const SizedBox.shrink();
        final day = index - leadingBlanks + 1;
        final items = byDay[day] ?? const <KnowledgeItem>[];

        return InkWell(
          key: Key('calendar-day-$day'),
          onTap: items.isEmpty ? null : () => onTapDay(day, items),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day', style: theme.textTheme.bodyMedium),
              if (items.isNotEmpty)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
