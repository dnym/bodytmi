import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _set(
  String id,
  String load,
  String reps, [
  String status = 'completed',
]) => {
  'sourceId': id,
  'ordinal': int.parse(id.substring(1)),
  'role': 'work',
  'status': status,
  'actuals': {
    'load': {'value': load, 'unit': 'kg'},
    'reps': {'value': reps, 'unit': 'rep'},
  },
};

Map<String, Object?> _session(String id, String date, List<Object?> sets) => {
  'sourceId': id,
  'date': date,
  'exercises': [
    {
      'sourceId': '$id/1',
      'order': 1,
      'name': 'Squat',
      'exerciseId': 'squat',
      'sets': sets,
    },
  ],
};

final _document = {
  'format': 'bodytmi-history-import/1',
  'source': {'namespace': 'old-log'},
  'sessions': [
    _session('h1', '2026-01-05', [
      _set('s1', '100', '5'),
      _set('s2', '100', '6'),
    ]),
    _session('h2', '2026-01-12', [
      _set('s1', '100', '6'),
      _set('s2', '100', '8', 'interrupted'),
      _set('s3', '105', '5'),
    ]),
  ],
};

void extendedRecordsTests() {
  test('imported records stay in exact imported contexts', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-irec-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await HistoryImportService(store).apply(
        HistoryImportDocument.fromJson(jsonDecode(jsonEncode(_document))),
        at: parseInstant('2026-02-01T10:00:00Z', 'at'),
        atText: '2026-02-01T10:00:00Z',
        onChanged: 'reject',
        confirm: true,
      );
      final report = importedRecordsBlock(
        await store.importedSessions(),
        metric: 'reps',
        direction: 'higher',
      );
      equal(
        jsonObject(report['policy'], 'p')['id'],
        'bodytmi-imported-records/1',
      );
      equal(report['eligibleCount'], 4);
      equal(report['excludedCount'], 1);
      equal(
        jsonObject(jsonList(report, 'excluded').single, 'e')['reason'],
        'status-interrupted',
      );
      // 100 kg and 105 kg are held fixed separately.
      final groups = [
        for (final g in jsonList(report, 'groups')) jsonObject(g, 'g'),
      ];
      equal(groups.length, 2);
      final at100 = groups.firstWhere(
        (g) => canonicalJson(g['heldActuals']).contains('"100"'),
      );
      equal(jsonObject(at100['best'], 'b')['value'], '6');
      jsonEqual(
        [
          for (final p in jsonList(at100, 'points'))
            jsonObject(p, 'p')['marker'],
        ],
        ['initial', 'record', 'tie'],
      );
      equal(jsonList(at100, 'bestSources').length, 2);
      final conditioned = importedRecordsBlock(
        await store.importedSessions(),
        metric: 'reps',
        direction: 'higher',
        atActuals: {'load': Quantity('105', 'kg')},
      );
      equal(jsonList(conditioned, 'groups').length, 1);
      final scoped = importedRecordsBlock(
        await store.importedSessions(),
        metric: 'reps',
        direction: 'higher',
        context: {'slotId': 'squat'},
      );
      equal(jsonObject(scoped['selectionExcluded'], 'x')['all'], true);
      await store.close();

      Future<({int code, String output, String error})> records(
        Map<String, Object?> input,
      ) => invoke(
        ['store', 'records'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '${dir.path}/db.sqlite',
          'metric': 'reps',
          'direction': 'higher',
          ...input,
        }),
      );
      final plain = await records({});
      check(plain.code == 0, plain.error);
      check(!plain.output.contains('"imported"'));
      final ok = await records({
        'includeImported': true,
        'importNamespace': 'old-log',
      });
      check(ok.code == 0, ok.error);
      final data = jsonObject(
        jsonObject(jsonDecode(ok.output), 'r')['data'],
        'data',
      );
      equal(jsonObject(data['imported'], 'i')['eligibleCount'], 4);
      equal((await records({'importNamespace': 'old-log'})).code, 2);
      equal((await records({'amrapId': 'finisher'})).code, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
