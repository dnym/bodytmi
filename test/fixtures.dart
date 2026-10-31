import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';

Map<String, Object?> example(String name) =>
    jsonDecode(File('examples/$name.json').readAsStringSync())
        as Map<String, Object?>;
Map<String, Object?> copyJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;
WorkoutDefinition definition() =>
    WorkoutDefinition.fromJson(example('upper-a')['definition']);
WorkoutRevision revision() => WorkoutRevision.publish(definition());
DateTime instant(int day) => DateTime.utc(2026, 10, day, 12);
TrainingSession start({
  String id = 'session-1',
  int day = 1,
  WorkoutRevision? from,
  List<TrainingSession> history = const [],
}) => const TrainingService().start(
  sessionId: id,
  revision: from ?? revision(),
  startedAt: instant(day),
  history: history,
);
TrainingSession finished(TrainingSession session) {
  for (final set in session.sets) {
    session = const TrainingService().complete(
      session,
      set.id,
      const {},
      acceptSuggested: true,
    );
  }
  return session.finish(session.startedAt.add(const Duration(hours: 1)));
}

Metrics metrics(Map<String, (String, String)> input) => {
  for (final e in input.entries) e.key: Quantity(e.value.$1, e.value.$2),
};
