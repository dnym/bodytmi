import 'package:bodytmi_core/bodytmi_core.dart';
import 'body_service.dart';
import 'training_repository.dart';

const _methodKind = 'maintenance-method';

/// Maintenance energy (F4) and the diet category from the body report.
final class EnergyService {
  const EnergyService(this.repository);
  final TrainingRepository repository;

  Future<List<MaintenanceMethodRevision>> methods() async => [
    for (final r in await repository.dietRecords(kind: _methodKind))
      MaintenanceMethodRevision.fromJson(r.snapshot),
  ]..sort((a, b) => a.number.compareTo(b.number));

  /// Selects the maintenance method in force from [from]; compare-and-set
  /// on the latest selection number.
  Future<MaintenanceMethodRevision> selectMethod(
    String from,
    MaintenanceMethod method,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await methods();
    final before = all.isEmpty ? null : all.last;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Maintenance method changed.');
    final next = MaintenanceMethodRevision.publish(
      from,
      method,
      previous: before,
    );
    await repository.saveDietRecord(
      DietRecord(_methodKind, 'maintenance', next.number, next.toJson()),
    );
    return next;
  });

  /// Inputs for energy formulas taken from a body report, each with the
  /// report's provenance, plus the diet category.
  static ({EnergyInputs inputs, Map<String, Object?> shown}) inputsFrom(
    Map<String, Object?> report,
    String asOfDate,
    Profile profile,
  ) {
    final measures = jsonObject(report['measures'], 'measures');
    final calculations = jsonObject(report['calculations'], 'calculations');
    final source = jsonObject(report['bodyFatSource'], 'bodyFatSource');
    double? value(Map<String, Object?> r) => r['status'] == 'resolved'
        ? double.parse(Quantity.fromJson(r['value']).value.toString())
        : null;
    Map<String, Object?> show(Map<String, Object?> r) => {
      'status': r['status'],
      if (r['status'] == 'resolved') ...{
        'value': r['value'],
        for (final f in ['observedOn', 'ageDays', 'stale', 'used', 'estimate'])
          if (r[f] != null) f: r[f],
      } else
        'reason': r['reason'],
    };
    final mass = jsonObject(measures['mass'], 'mass');
    final height = jsonObject(measures['height'], 'height');
    final ffm = jsonObject(calculations['fat-free-mass'], 'fat-free-mass');
    final heightM = value(height);
    final sex = profile.sex;
    final fraction = source['status'] == 'resolved'
        ? Quantity.fromJson(source['value']).value
        : null;
    final category = fraction == null || sex == null
        ? null
        : dietCategory(fraction, sex);
    final age = profile.ageOn(asOfDate);
    return (
      inputs: (
        massKg: value(mass),
        heightCm: heightM == null ? null : heightM * 100,
        fatFreeMassKg: value(ffm),
        age: age,
        sex: sex,
        category: category,
      ),
      shown: {
        'mass': show(mass),
        'height': show(height),
        'fatFreeMass': show(ffm),
        'bodyFat': {
          'status': source['status'],
          if (fraction != null) 'value': source['value'],
          'origin': source['origin'],
          'source': source['source'],
          if (source['reason'] != null) 'reason': source['reason'],
        },
        'sex': sex,
        'age': age,
        'category': category == null
            ? {
                'status': 'unavailable',
                'reason': sex == null
                    ? 'The profile has no sex.'
                    : 'The body-fat source is unavailable.',
              }
            : {
                'status': 'resolved',
                'value': category,
                'policy': dietCategoryPolicy,
              },
      },
    );
  }

  /// Policy bodytmi-energy-estimate/1: the maintenance method in force (or
  /// [method]) evaluated at [asOfText] from the body report.
  Future<Map<String, Object?>> estimate(
    String asOfText, {
    String context = 'health',
    MaintenanceMethod? method,
  }) => repository.transaction(() async {
    parseInstant(asOfText, 'asOf');
    final asOfDate = asOfText.substring(0, 10);
    final body = BodyService(repository);
    final report = await body.report(asOfText, context: context);
    final profile = (await body.profile())?.profile ?? Profile.empty;
    final (:inputs, :shown) = inputsFrom(report, asOfDate, profile);
    final selected = method == null
        ? maintenanceMethodOn(asOfDate, await methods())
        : null;
    final chosen = method ?? selected?.method;
    return {
      'policy': 'bodytmi-energy-estimate/1',
      'asOf': asOfText,
      'context': context,
      'methodOrigin': method != null
          ? 'request'
          : selected == null
          ? 'none'
          : 'selected',
      'methodRevision': ?selected?.number,
      'inputs': shown,
      'maintenance': chosen == null
          ? {
              'status': 'unavailable',
              'reason':
                  'No maintenance method is selected; choose one with '
                  'energy method.',
            }
          : chosen.evaluate(inputs),
    };
  });
}
