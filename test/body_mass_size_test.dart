import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _weighIn(int day) => {
  'id': 'w$day',
  'context': 'clothed-training',
  'observedAt': DateTime.utc(
    2025,
    1,
    1,
  ).add(Duration(days: day)).toIso8601String(),
  'mass': {'value': '${80 + day % 3}.${day % 10}', 'unit': 'kg'},
  'source': 'bathroom scale',
};

void bodyMassSizeTests() {
  test('a session freezes its body mass at constant size, however long the '
      'weigh-in history', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-mass-size-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(
        WorkoutDefinition.fromJson(
          example('effective-load-practice')['definition'],
        ),
        0,
      );
      await mass.save(_weighIn(0), 0);
      final early = await training.start(
        'early',
        'effective-load-practice',
        1,
        DateTime.utc(2025, 1, 2),
      );
      for (var day = 1; day < 400; day++) await mass.save(_weighIn(day), 0);
      final late = await training.start(
        'late',
        'effective-load-practice',
        1,
        DateTime.utc(2026, 3, 1),
      );
      int size(TrainingSession s) => jsonEncode(s.toJson()).length;
      // Only digits of counts, masses and times differ.
      check(
        (size(late) - size(early)).abs() < 64,
        '${size(early)} vs ${size(late)}',
      );
      final input = late.bodyMassInputs.values.single;
      equal(input.resolution.source, 'trend');
      equal(input.resolution.sourceFingerprint['sourceCount'], 400);
      // A later correction of an old weigh-in is still reported.
      equal(
        input.freshness([
          for (final r in await store.bodyMassRecords()) r.measurement,
        ])['changed'],
        false,
      );
      await mass.save({..._weighIn(3), 'notes': 'Corrected'}, 1);
      equal(
        input.freshness([
          for (final r in await store.bodyMassRecords()) r.measurement,
        ])['changed'],
        true,
      );
      jsonEqual(sessionFromJson(late.toJson()).toJson(), late.toJson());
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
