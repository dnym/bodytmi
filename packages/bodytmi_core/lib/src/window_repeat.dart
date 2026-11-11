import 'errors.dart';
import 'workout.dart';

/// A deadline-bounded repeat specification for one finite round template.
/// Limits are safety bounds; reaching one is not a completed workout.
final class WindowRepeatSpec {
  const WindowRepeatSpec._(
    this.id,
    this.durationMilliseconds,
    this.maxRounds,
    this.maxOccurrences,
    this.roundDefinition,
  );

  factory WindowRepeatSpec.fromJson(Object? input) {
    final json = jsonObject(input, 'window repeat');
    checkKeys(json, {
      'id',
      'durationMilliseconds',
      'maxRounds',
      'maxOccurrences',
      'roundDefinition',
    });
    int bounded(String key, int max) {
      final value = json[key];
      if (value is! int || value < 1 || value > max)
        invalid('$key must be an integer from 1 through $max.');
      return value;
    }

    return WindowRepeatSpec._(
      identifier(json, 'id'),
      bounded('durationMilliseconds', 2000000000),
      bounded('maxRounds', 10000),
      bounded('maxOccurrences', 10000),
      WorkoutDefinition.fromJson(json['roundDefinition']),
    );
  }

  final String id;
  final int durationMilliseconds, maxRounds, maxOccurrences;
  final WorkoutDefinition roundDefinition;

  Map<String, Object?> toJson() => {
    'id': id,
    'durationMilliseconds': durationMilliseconds,
    'maxRounds': maxRounds,
    'maxOccurrences': maxOccurrences,
    'roundDefinition': roundDefinition.toJson(),
  };
}
