import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'support.dart';

void activityTests() {
  test(
    'requested nested walk/run plan has 72 efforts and only two outer rests',
    () {
      final plan = Activity.fromJson({
        'id': 'blocks',
        'type': 'repeat',
        'count': 3,
        'restBetweenSeconds': 120,
        'child': {
          'id': 'rounds',
          'type': 'repeat',
          'count': 12,
          'child': {
            'id': 'pair',
            'type': 'sequence',
            'children': [
              {'id': 'walk', 'type': 'effort', 'slot': 'walk'},
              {'id': 'run', 'type': 'effort', 'slot': 'run'},
            ],
          },
        },
      });
      final occurrences = plan.occurrences().toList();
      equal(occurrences.where((o) => o.activity is Effort).length, 72);
      final rests = occurrences.map((o) => o.activity).whereType<Rest>();
      equal(rests.length, 2);
      equal(rests.fold<int>(0, (sum, rest) => sum + rest.durationSeconds), 240);
      equal(occurrences.map((o) => o.id).toSet().length, 74);
      equal(72 * 30 + 240, 40 * 60);
      jsonEqual(Activity.fromJson(plan.toJson()).toJson(), plan.toJson());
    },
  );
  test('window structure preserves deadlines without claiming execution', () {
    final plan = Activity.fromJson({
      'id': 'minute',
      'type': 'window',
      'durationSeconds': 60,
      'child': {'id': 'set', 'type': 'effort', 'slot': 'clean'},
    });
    check(plan is TimeWindow);
    equal((plan as TimeWindow).durationSeconds, 60);
    equal(plan.occurrences().single.id, 'minute/set');
  });
  test('duplicate IDs and unknown slots fail before a session is created', () {
    final input = definition().toJson();
    input['plan'] = {
      'id': 'dup',
      'type': 'sequence',
      'children': [
        {'id': 'same', 'type': 'effort', 'slot': 'bench-heavy'},
        {'id': 'same', 'type': 'effort', 'slot': 'bench-light'},
      ],
    };
    rejects(() => WorkoutDefinition.fromJson(input));
    input['plan'] = {'id': 'bad', 'type': 'effort', 'slot': 'missing'};
    rejects(() => WorkoutDefinition.fromJson(input));
  });
  test('invalid/empty/oversized plans fail with resource errors', () {
    rejects(
      () => Activity.fromJson({
        'id': 'bad',
        'type': 'sequence',
        'children': <Object?>[],
      }),
    );
    rejects(
      () => Activity.fromJson({
        'id': 'bad',
        'type': 'repeat',
        'count': -1,
        'child': <String, Object?>{},
      }),
    );
    final input = definition().toJson();
    input['plan'] = {
      'id': 'many',
      'type': 'repeat',
      'count': 10001,
      'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
    };
    rejects(() => WorkoutDefinition.fromJson(input));
  });
}
