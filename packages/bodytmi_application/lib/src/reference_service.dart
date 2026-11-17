import 'package:bodytmi_core/bodytmi_core.dart';

import 'body_service.dart';
import 'diary_service.dart';
import 'diet_service.dart';
import 'food_service.dart';
import 'training_repository.dart';

/// Nordic reference values (NNR 2023) against mean intake over complete
/// diary days. Reference values describe intake averaged over time, so they
/// are kept apart from your own plan targets and never change them.
final class ReferenceService {
  const ReferenceService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> assess(
    String from,
    String until, {
    String context = 'health',
  }) => repository.transaction(() async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final count = daysBetween(from, until);
    if (count < 1 || count > 366) invalid('A reference period is 1–366 days.');
    final last = addDays(until, -1);
    final profile = (await BodyService(repository).profile())?.profile;
    final sex = profile?.sex;
    final age = profile?.ageOn(last);
    if (sex == null || age == null)
      invalid('Reference values need sex and birth date in the profile.');
    final references = nnr2023References(sex, age);

    final math = FoodMath(await FoodService(repository).lookup());
    final entries = await repository.diaryEntries(
      fromDate: from,
      untilDate: until,
    );
    final marks = {
      for (final r in await repository.dietRecords(kind: diaryDayKind))
        (r.snapshot['date']! as String): DiaryDayMark.fromJson(r.snapshot),
    };
    final days = <Nutrition>[];
    for (var i = 0; i < count; i++) {
      final date = addDays(from, i);
      var total = Nutrition.empty;
      var n = 0;
      for (final e in entries) {
        if (e.date != date) continue;
        total += e.nutrition(math);
        n++;
      }
      if (diaryDayStatus(marks[date], n) == 'complete') days.add(total);
    }
    // An empty complete day declares every nutrient as zero.
    bool known(Nutrition d, String id) =>
        d.items == 0 || d.status(id) == 'known';
    Fraction value(Nutrition d, String id) =>
        d.items == 0 ? Fraction.zero : d.display(id)!;

    MeanIntake mean(String id) {
      var sum = Fraction.zero;
      var n = 0, partial = 0;
      for (final d in days) {
        if (known(d, id)) {
          sum += value(d, id);
          n++;
        } else {
          partial++;
        }
      }
      return (
        value: n == 0 ? null : sum / Fraction.integer(n),
        days: n,
        partialDays: partial,
      );
    }

    JointMean joint(List<String> parts) {
      final ids = ['energy', ...parts];
      final sums = {for (final id in ids) id: Fraction.zero};
      var n = 0;
      for (final d in days) {
        if (!ids.every((id) => known(d, id))) continue;
        for (final id in ids) {
          sums[id] = sums[id]! + value(d, id);
        }
        n++;
      }
      if (n == 0) return (energyKcal: null, parts: const {}, days: 0);
      final div = Fraction.integer(n);
      return (
        energyKcal: sums['energy']! / div,
        parts: {for (final p in parts) p: sums[p]! / div},
        days: n,
      );
    }

    final inputs = await DietService(
      repository,
    ).currentInputs('${until}T00:00:00Z', context: context);
    final mass = inputs.frozen['mass'] as Map<String, Object?>?;
    final rows = assessReferences(
      references,
      mean: mean,
      joint: joint,
      bodyMassKg: mass == null
          ? null
          : Fraction.parse(mass['value']! as String),
    );
    return {
      'policy': nnr2023Policy,
      'source':
          'Nordic Nutrition Recommendations 2023 (Nordic Council of '
          'Ministers), adult tables.',
      'from': from,
      'until': until,
      'sex': sex,
      'age': age,
      'completeDays': days.length,
      'days': count,
      'bodyMass': mass,
      if (days.length < 7)
        'warning':
            'Reference values describe intake averaged over time; fewer '
            'than 7 complete days say little about adequacy.',
      'notModelled':
          'Pregnancy, lactation and children; vitamin K, pantothenic acid, '
          'biotin, choline, copper, fluoride, manganese and molybdenum are '
          'not in the food vocabulary.',
      'references': rows,
      'notCompared': nnr2023NotCompared,
    };
  });
}
