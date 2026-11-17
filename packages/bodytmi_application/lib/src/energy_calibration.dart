import 'package:bodytmi_core/bodytmi_core.dart';

import 'diary_service.dart';
import 'diet_service.dart';
import 'training_repository.dart';

const calibrationPolicy = 'bodytmi-energy-calibration/1';

/// Maintenance energy calibrated from the diary (F4), offered beside the
/// formula in force, never replacing it on its own.
///
/// Expenditure = mean intake over complete diary days − energy of the trend
/// mass change per day. The change is split into fat and lean by the Forbes
/// curve at the mean fat mass, with Hall's energy densities (the same model
/// as the plan simulation). McDonald (IMF, ch. 14) asks for tracking that
/// includes at least two weekdays and one weekend day, and says tracked
/// intake and a formula estimate within 100–200 kcal agree, while 300 kcal
/// or more apart means intake or activity was mis-measured.
final class EnergyCalibrationService {
  const EnergyCalibrationService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> calibrate(
    String from,
    String until, {
    String context = 'health',
    int minimumDays = 14,
  }) => repository.transaction(() async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final days = daysBetween(from, until);
    if (days < 7 || days > 366)
      invalid('A calibration window is 7 to 366 days.');
    if (minimumDays < 3 || minimumDays > days)
      invalid('minimumDays is from 3 to the window length.');
    final report = await DiaryService(
      repository,
    ).report(from, until, nutrients: const ['energy']);
    final daily = (report['daily']! as List).cast<Map<String, Object?>>();
    var weekdays = 0, weekend = 0, energyUnknown = 0;
    for (final d in daily) {
      if (d['status'] != 'complete') continue;
      final weekday = DateTime.parse('${d['date']}T00:00:00Z').weekday;
      if (weekday >= DateTime.saturday) {
        weekend++;
      } else {
        weekdays++;
      }
      final energy = jsonObject(
        jsonObject(jsonObject(d['totals'], 't')['nutrients'], 'n')['energy'],
        'e',
      );
      if (d['entries'] != 0 && energy['status'] != 'known') energyUnknown++;
    }
    final complete = weekdays + weekend;
    final mean = jsonObject(
      jsonObject(
        jsonObject(
          jsonObject(report['averages'], 'a')['completeDays'],
          'c',
        )['nutrients'],
        'n',
      )['energy'],
      'e',
    );
    final reasons = <String>[
      if (complete < minimumDays)
        'Only $complete complete diary days; $minimumDays are required.',
      if (weekdays < 2 || weekend < 1)
        'Complete days need at least two weekdays and one weekend day.',
      if (energyUnknown > 0)
        '$energyUnknown complete days include items without energy.',
    ];
    final diet = DietService(repository);
    final start = await diet.currentInputs(
      '${from}T00:00:00Z',
      context: context,
    );
    final end = await diet.currentInputs(
      '${until}T00:00:00Z',
      context: context,
    );
    final m0 = start.inputs.massKg, m1 = end.inputs.massKg;
    final f0 = start.inputs.fatFreeMassKg, f1 = end.inputs.fatFreeMassKg;
    if (m0 == null || m1 == null)
      reasons.add('The trend mass is unavailable at the window ends.');
    final ffm = [?f0, ?f1];
    if (ffm.isEmpty)
      reasons.add('Fat-free mass is unavailable, so the change cannot split.');
    final body = <String, Object?>{
      'policy': calibrationPolicy,
      'from': from,
      'until': until,
      'context': context,
      'days': days,
      'diary': {
        'completeDays': complete,
        'weekdays': weekdays,
        'weekendDays': weekend,
        'daysWithUnknownEnergy': energyUnknown,
        'counts': report['counts'],
        'meanIntake': mean['value'] == null
            ? null
            : {'value': mean['value'], 'unit': 'kcal'},
      },
      'mass': {'start': start.frozen['mass'], 'end': end.frozen['mass']},
      'fatFreeMass': {
        'start': start.frozen['fatFreeMass'],
        'end': end.frozen['fatFreeMass'],
      },
      'source':
          'Intake from complete diary days; mass change from the trend; '
          'lean share C/(C + fat) with C = $forbesC kg (Forbes); fat '
          '$fatMJPerKg MJ/kg, lean $leanMJPerKg MJ/kg (Hall 2008). '
          'Agreement bands: McDonald, Intermittent Modified Fasting (2026), '
          'ch. 14.',
    };
    if (reasons.isNotEmpty || mean['value'] == null)
      return {
        ...body,
        'status': 'insufficient',
        'reasons': reasons.isEmpty ? ['No complete diary days.'] : reasons,
      };
    final intake = double.parse(mean['value']! as String);
    final massChange = m1! - m0!;
    final fatMass = (m0 + m1) / 2 - ffm.reduce((a, b) => a + b) / ffm.length;
    final leanShare = forbesC / (forbesC + (fatMass > 0 ? fatMass : 0.001));
    final kcalPerKg =
        (leanShare * leanMJPerKg + (1 - leanShare) * fatMJPerKg) / 0.004184;
    final stored = massChange * kcalPerKg / days;
    final expenditure = intake - stored;
    final endFormula = end.frozen['maintenance'] as Map<String, Object?>?;
    Map<String, Object?>? comparison;
    if (endFormula != null) {
      final value = double.parse(endFormula['value']! as String);
      final diff = expenditure - value;
      final band = diff.abs() <= 200
          ? 'agrees'
          : diff.abs() < 300
          ? 'between'
          : 'disagrees';
      comparison = {
        'formula': endFormula,
        'difference': {'value': round9(diff), 'unit': 'kcal'},
        'band': band,
      };
    }
    return {
      ...body,
      'status': 'calibrated',
      'factors': {
        'massChange': {'value': round9(massChange), 'unit': 'kg'},
        'meanFatMass': {'value': round9(fatMass), 'unit': 'kg'},
        'leanShare': round9(leanShare),
        'energyPerKg': {'value': round9(kcalPerKg), 'unit': 'kcal'},
        'storedPerDay': {'value': round9(stored), 'unit': 'kcal'},
      },
      'value': {'value': round9(expenditure), 'unit': 'kcal'},
      'comparison': ?comparison,
      if (comparison == null)
        'comparisonReason': 'No maintenance formula resolves at the end.',
      'adopt':
          'To use this value, select it with energy method '
          '{formula: manual, energy}.',
    };
  });
}
