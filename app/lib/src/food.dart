import 'package:material_ui/material_ui.dart';

import 'diary_edit.dart';
import 'format.dart';
import 'my_foods.dart';
import 'profile.dart';
import 'today.dart' show FoodSummary;
import 'widgets.dart';

/// The Food tab: one diary day with its budget, entries by meal.
final class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, this.clock});
  final DateTime? clock;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

final class _FoodScreenState extends State<FoodScreen> {
  int dayOffset = 0;

  DateTime get _day {
    final now = widget.clock ?? DateTime.now();
    return DateTime(now.year, now.month, now.day + dayOffset);
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => setState(() => dayOffset--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  dayOffset == 0 ? 'Today' : f.longDate(_day),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: dayOffset >= 0
                    ? null
                    : () => setState(() => dayOffset++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: ProfileLoader<Map<String, Object?>>(
            key: ValueKey(dayOffset),
            load: (p) => p.call('diary day', {'date': isoDate(_day)}),
            builder: (context, diary) {
              final meals = <String, List<Map<String, Object?>>>{};
              for (final e in (diary['entries'] as List?) ?? const []) {
                final meal = '${at(e, ['entry', 'meal']) ?? 'Other'}';
                meals
                    .putIfAbsent(meal, () => [])
                    .add(e as Map<String, Object?>);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => openMyFoods(context),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('My foods & recipes'),
                    ),
                  ),
                  SectionCard(
                    title:
                        at(diary, ['budget', 'dayType', 'name']) as String? ??
                        'Totals',
                    trailing: Pill(
                      '${diary['status']}',
                      warn: diary['status'] != 'complete',
                    ),
                    child: FoodSummary(
                      diary: diary,
                      energy: at(diary, [
                        'budget',
                        'goals',
                        'energy',
                      ]) as Map<String, Object?>?,
                    ),
                  ),
                  if (meals.isEmpty)
                    const SectionCard(child: EmptyNote('Nothing logged.')),
                  for (final MapEntry(key: meal, value: entries)
                      in meals.entries)
                    SectionCard(
                      title:
                          '$meal · ${f.clock(at(entries.first, ['entry', 'at']))}',
                      trailing: Muted(
                        '${f.number(entries.fold<double>(0, (a, e) => a + (double.tryParse('${at(e, ['nutrition', 'nutrients', 'energy', 'value'])}') ?? 0)), digits: 0)} kcal',
                      ),
                      child: Column(
                        children: [
                          for (final e in entries)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => editDiaryEntry(context, e),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${e['foodName'] ?? 'Quick entry'}',
                                          ),
                                          Muted(_amount(f, at(e, ['entry']))),
                                        ],
                                      ),
                                    ),
                                    Muted(
                                      f.number(
                                        at(e, [
                                          'nutrition',
                                          'nutrients',
                                          'energy',
                                          'value',
                                        ]),
                                        digits: 0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String _amount(Fmt f, Object? entry) {
    final amount = at(entry, ['amount']);
    if (amount is! Map) return '';
    if (amount['portion'] != null) {
      return '${f.number(amount['count'])} × ${amount['portion']}';
    }
    final entered = amount['entered'] ?? amount;
    return f.quantity(entered, digits: 2);
  }
}
