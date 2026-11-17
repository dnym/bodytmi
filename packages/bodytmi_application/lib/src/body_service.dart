import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'observation_service.dart';
import 'training_repository.dart';

/// Profile facts, body-fat source selection and the body report: every
/// body measure resolved at a time, and every calculation with its inputs'
/// ages, policies and sources.
final class BodyService {
  const BodyService(this.repository);
  final TrainingRepository repository;

  Future<ProfileRevision?> profile() async {
    final all = await repository.profileRevisions();
    return all.isEmpty
        ? null
        : all.reduce((a, b) => a.number > b.number ? a : b);
  }

  /// Replaces the profile; compare-and-set on its revision.
  Future<ProfileRevision> setProfile(Profile profile, int expectedRevision) =>
      repository.transaction(() async {
        final before = await this.profile();
        if ((before?.number ?? 0) != expectedRevision)
          throw const BodyTmiException('conflict', 'Profile changed.');
        if (before != null &&
            canonicalJson(before.profile.toJson()) ==
                canonicalJson(profile.toJson()))
          return before;
        final next = ProfileRevision.publish(profile, previous: before);
        await repository.insertProfileRevision(next);
        return next;
      });

  /// Records a body-fat source selection in force from [from]; compare-and-
  /// set on the latest selection number.
  Future<BodyFatSourceRevision> selectSource(
    String from,
    BodyFatSource source,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.bodyFatSourceRevisions();
    final before = all.isEmpty
        ? null
        : all.reduce((a, b) => a.number > b.number ? a : b);
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Body-fat source changed.');
    final next = BodyFatSourceRevision.publish(from, source, previous: before);
    await repository.insertBodyFatSourceRevision(next);
    return next;
  });

  static const _sites = ['waist', 'navel', 'hip', 'neck'];
  static const _skinfolds = [
    'chest',
    'midaxillary',
    'triceps',
    'subscapular',
    'abdomen',
    'suprailiac',
    'thigh',
  ];

  /// Everything resolved and calculated at [asOfText] (policy
  /// `bodytmi-body-report/1`). Body mass uses [context].
  Future<Map<String, Object?>> report(
    String asOfText, {
    String context = 'health',
  }) => repository.transaction(() async {
    parseInstant(asOfText, 'asOf');
    final asOfDate = asOfText.substring(0, 10);
    final observations = ObservationService(repository);
    final profile = (await this.profile())?.profile ?? Profile.empty;
    final resolved = <String, Map<String, Object?>>{};
    Future<Map<String, Object?>> resolve(
      String key,
      String measure,
      Map<String, String> attributes,
    ) async => resolved[key] = (await observations.resolve(
      measure,
      asOfText,
      attributes: attributes,
    )).toJson();

    await resolve('mass', 'body-mass', {'context': context});
    await resolve('height', 'height', const {});
    for (final site in _sites) {
      await resolve(site, 'circumference', {'site': site});
    }
    for (final site in _skinfolds) {
      await resolve('skinfold:$site', 'skinfold', {'site': site});
    }
    for (final method in BodyFatSource.seriesMethods) {
      await resolve('bodyFat:$method', 'body-fat', {'method': method});
    }
    await resolve('steps', 'steps', const {});

    Quantity? q(String key) {
      final r = resolved[key];
      return r == null || r['status'] != 'resolved'
          ? null
          : Quantity.fromJson(r['value']);
    }

    Map<String, Object?> provenance(String key) {
      final r = resolved[key]!;
      return {
        for (final field in [
          'measure',
          'observedOn',
          'ageDays',
          'stale',
          'used',
          'estimate',
          'policySource',
        ])
          if (r[field] != null) field: r[field],
      };
    }

    Map<String, Object?> calc(
      String name,
      Map<String, String> inputs, {
      Map<String, Object?> facts = const {},
      Map<String, Object?> extra = const {},
    }) {
      final supplied = <String, Object?>{...facts};
      final sources = <String, Object?>{};
      for (final e in inputs.entries) {
        if (e.value.startsWith('=')) continue;
        supplied[e.key] = q(e.value);
        if (resolved[e.value]?['status'] == 'resolved')
          sources[e.key] = provenance(e.value);
      }
      return calculation(
        'bodytmi-calc/$name/1',
      ).evaluate(supplied, provenance: sources);
    }

    final sex = profile.sex;
    final results = <String, Map<String, Object?>>{
      'bmi': calc('bmi', {'mass': 'mass', 'height': 'height'}),
      'waist-to-height': calc('waist-to-height', {
        'waist': 'waist',
        'height': 'height',
      }),
      'waist-to-hip': calc(
        'waist-to-hip',
        {'waist': 'waist', 'hip': 'hip'},
        facts: {'sex': sex},
      ),
      'waist-risk': calc('waist-risk', {'waist': 'waist'}, facts: {'sex': sex}),
      'navy-body-fat': calc(
        'navy-body-fat',
        {
          'navel': 'navel',
          'waist': 'waist',
          'hip': 'hip',
          'neck': 'neck',
          'height': 'height',
        },
        facts: {'sex': sex},
      ),
    };
    // Skinfold estimates need every site measured on one day; age is taken
    // on that day.
    for (final (name, sites) in [
      (
        'jackson-pollock-3',
        sex == 'female'
            ? ['triceps', 'suprailiac', 'thigh']
            : ['chest', 'abdomen', 'thigh'],
      ),
      ('jackson-pollock-7', _skinfolds),
    ]) {
      final days = {
        for (final site in sites)
          if (resolved['skinfold:$site']!['status'] == 'resolved')
            resolved['skinfold:$site']!['observedOn'],
      };
      if (days.length > 1) {
        results[name] = {
          'calculation': 'bodytmi-calc/$name/1',
          'status': 'unavailable',
          'reason':
              'Its skinfold sites were measured on different days '
              '(${(days.toList()..sort()).join(', ')}).',
        };
        continue;
      }
      results[name] = calc(
        name,
        {for (final site in sites) site: 'skinfold:$site'},
        facts: {
          'sex': sex,
          'age': days.isEmpty ? null : profile.ageOn(days.single! as String),
        },
      );
    }

    // The body-fat source in force on the report date.
    final selected = bodyFatSourceOn(
      asOfDate,
      await repository.bodyFatSourceRevisions(),
    );
    Map<String, Object?> sourceValue(BodyFatSource source) {
      if (source.kind == 'calculation') {
        final r = results[source.json['calculation']]!;
        return {
          'source': source.toJson(),
          'status': r['status'],
          if (r['status'] == 'resolved') 'value': r['value'],
          if (r['status'] != 'resolved') 'reason': r['reason'],
        };
      }
      final method = source.json['method']! as String;
      final r = source.json['device'] == null
          ? resolved['bodyFat:$method']!
          : null;
      return {
        'source': source.toJson(),
        if (r == null) ...{
          'status': 'unavailable',
          'reason': 'Device-specific series are resolved separately.',
        } else ...{
          'status': r['status'],
          if (r['status'] == 'resolved') ...{
            'value': r['value'],
            'provenance': provenance('bodyFat:$method'),
          } else
            'reason': r['reason'],
        },
      };
    }

    late final Map<String, Object?> bodyFat;
    if (selected.source.kind == 'mean') {
      final parts = [
        for (final c in selected.source.components) sourceValue(c),
      ];
      final missing = parts.where((p) => p['status'] != 'resolved');
      if (missing.isNotEmpty) {
        bodyFat = {
          'status': 'unavailable',
          'reason':
              'A mean needs every component; '
              '${missing.length} of ${parts.length} are unavailable.',
          'components': parts,
        };
      } else {
        final values = [
          for (final p in parts) Quantity.fromJson(p['value']).value,
        ];
        bodyFat = {
          'status': 'resolved',
          'value': {
            'value': values
                .reduce((a, b) => a + b)
                .dividedByInt(values.length)
                .toString(),
            'unit': 'ratio',
          },
          'components': parts,
        };
      }
    } else {
      bodyFat = sourceValue(selected.source);
    }
    final fraction = bodyFat['status'] == 'resolved'
        ? Quantity.fromJson(bodyFat['value'])
        : null;
    Map<String, Object?> fatCalc(String name, Map<String, String> inputs) {
      final r = calc(name, inputs);
      if (fraction == null) return r;
      return calculation('bodytmi-calc/$name/1').evaluate(
        {
          for (final e in inputs.entries) e.key: q(e.value),
          'bodyFat': fraction,
        },
        provenance: {
          for (final e in inputs.entries)
            if (resolved[e.value]?['status'] == 'resolved')
              e.key: provenance(e.value),
          'bodyFat': {'bodyFatSource': selected.source.toJson()},
        },
      );
    }

    for (final name in ['fat-mass', 'fat-free-mass']) {
      results[name] = fatCalc(name, {'mass': 'mass'});
    }
    for (final name in ['ffmi', 'normalized-ffmi']) {
      results[name] = fatCalc(name, {'mass': 'mass', 'height': 'height'});
    }
    return {
      'policy': 'bodytmi-body-report/1',
      'asOf': asOfText,
      'context': context,
      'profile': profile.toJson(),
      'measures': resolved,
      'bodyFatSource': {
        'origin': selected.origin,
        'revision': ?selected.revision,
        ...bodyFat,
        if (selected.source.kind == 'mean') 'source': selected.source.toJson(),
      },
      'calculations': results,
    };
  });
}
