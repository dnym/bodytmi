import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Map<String, Object?> _set(
  String id,
  int ordinal, {
  String role = 'work',
  String status = 'completed',
  String? load,
  String unit = 'kg',
  String? reps = '5',
  Map<String, Object?>? extra,
}) => {
  'sourceId': id,
  'ordinal': ordinal,
  'role': role,
  'status': status,
  if (status != 'skipped')
    'actuals': {
      'load': ?(load == null ? null : _q(load, unit)),
      'reps': ?(reps == null ? null : _q(reps, 'rep')),
    },
  ...?extra,
};

Map<String, Object?> _exercise(
  String id,
  List<Map<String, Object?>> sets, {
  int order = 1,
  String name = 'Squat',
  Map<String, Object?>? extra,
}) => {'sourceId': id, 'order': order, 'name': name, 'sets': sets, ...?extra};

Map<String, Object?> _document({
  List<Map<String, Object?>>? sessions,
  List<Map<String, Object?>> measurements = const [],
  String namespace = 'old-log',
}) => {
  'format': 'bodytmi-history-import/1',
  'source': {'namespace': namespace, 'app': 'test'},
  'sessions':
      sessions ??
      [
        {
          'sourceId': 'h/1',
          'date': '2026-01-05',
          'exercises': [
            _exercise(
              'h/1/1',
              [
                _set('a', 1, role: 'warmup', load: '60'),
                _set('b', 2, load: '100'),
              ],
              extra: {'exerciseId': 'squat'},
            ),
          ],
        },
        {
          'sourceId': 'h/2',
          'startedAt': '2026-01-05T18:00:00+01:00',
          'finishedAt': '2026-01-05T19:00:00+01:00',
          'exercises': [
            _exercise(
              'h/2/1',
              [_set('a', 1, load: '105')],
              extra: {'exerciseId': 'squat'},
            ),
          ],
        },
      ],
  'measurements': measurements,
};

HistoryImportDocument _parse(Map<String, Object?> json) =>
    HistoryImportDocument.fromJson(jsonDecode(jsonEncode(json)));

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-import-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _apply(
  HistoryImportService service,
  Map<String, Object?> document, {
  String at = '2026-02-01T10:00:00Z',
  String onChanged = 'reject',
}) => service.apply(
  _parse(document),
  at: parseInstant(at, 'at'),
  atText: at,
  onChanged: onChanged,
  confirm: true,
);

Map<String, Object?> _counts(Map<String, Object?> report, String kind) =>
    jsonObject(jsonObject(report['counts'], 'counts')[kind], kind);

Future<Map<String, Object?>> _resign(Map<String, Object?> envelope) async {
  envelope.remove('sha256');
  envelope['sha256'] = sha256
      .convert(utf8.encode(canonicalJson(envelope)))
      .toString();
  return envelope;
}

final _measurement = {
  'id': 'old-mass-1',
  'sourceId': 'body/1',
  'context': 'imported-unclassified',
  'observedAt': '2026-01-05T07:00:00+01:00',
  'mass': _q('82.5', 'kg'),
};

void historyImportTests() {
  test('history import documents validate strictly and report unknowns', () {
    final document = _parse(_document());
    equal(document.sessions.length, 2);
    final unknowns = document.unknowns;
    equal(unknowns['dateOnlySessions'], 1);
    equal(unknowns['sets'], 3);
    // Mass was entered with no declared convention.
    equal(unknowns['exercisesWithMassButNoConvention'], 2);
    equal(unknowns['exercisesWithoutCatalogMapping'], 0);
    check(
      (unknowns['notRepresented'] as List).contains('workout-revision'),
      'the interchange states it carries no workout revisions',
    );
    // Sets normalize by ordinal regardless of source order.
    final reordered = _parse(
      _document(
        sessions: [
          {
            'sourceId': 'x',
            'date': '2026-01-01',
            'exercises': [
              _exercise('e', [_set('two', 2, load: '1'), _set('one', 1)]),
            ],
          },
        ],
      ),
    );
    equal(
      reordered.sessions.single.exercises.single.sets.first.sourceId,
      'one',
    );

    Map<String, Object?> session(Map<String, Object?> changes) => {
      'sourceId': 's',
      'date': '2026-01-01',
      'exercises': [
        _exercise('e', [_set('a', 1)]),
      ],
      ...changes,
    };
    void bad(Map<String, Object?> json) =>
        rejects(() => _parse(json), 'validation');
    bad({..._document(), 'format': 'neutral-training-log/0.1'});
    bad({
      ..._document(),
      'source': {'app': 'missing namespace'},
    });
    bad(
      _document(
        sessions: [
          session({'date': '2026-02-30'}),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({'startedAt': '2026-01-01T10:00:00Z'}),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          {
            ...session({}),
            'date': null,
            'startedAt': '2026-01-01T10:00:00Z',
            'finishedAt': '2026-01-01T09:00:00Z',
          }..remove('date'),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'exercises': [
              _exercise('e', [
                {
                  'sourceId': 'a',
                  'ordinal': 1,
                  'role': 'work',
                  'status': 'completed',
                },
              ]),
            ],
          }),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'exercises': [
              _exercise('e', [
                {
                  ..._set('a', 1, status: 'skipped'),
                  'actuals': {'reps': _q('5', 'rep')},
                },
              ]),
            ],
          }),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'exercises': [
              _exercise('e', [_set('a', 1, role: 'heavy')]),
            ],
          }),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'exercises': [
              _exercise('e', [
                _set(
                  'a',
                  1,
                  status: 'skipped',
                  extra: {
                    'observations': {
                      'rpe': {'value': '8', 'scale': '0-10'},
                    },
                  },
                ),
              ]),
            ],
          }),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'exercises': [
              _exercise('e', [
                _set(
                  'a',
                  1,
                  extra: {
                    'observations': {'terminationReason': 'interrupted'},
                  },
                ),
              ]),
            ],
          }),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'raw': {'weight': 100.5},
          }),
        ],
      ),
    );
    bad(
      _document(
        sessions: [
          session({
            'exercises': [
              _exercise('e', [_set('a', 1)], extra: {'implementationId': 'x'}),
            ],
          }),
        ],
      ),
    );
    bad(_document(sessions: [session({}), session({})]));
    bad(
      _document(
        sessions: [],
        measurements: [
          _measurement,
          {..._measurement, 'sourceId': 'body/2'},
        ],
      ),
    );
    bad(
      _document(
        sessions: [],
        measurements: [
          {..._measurement}..remove('context'),
        ],
      ),
    );
    bad(_document(sessions: [], measurements: []));
    // Integer and string raw fields survive verbatim.
    final raw = _parse(
      _document(
        sessions: [
          session({
            'raw': {
              'date': 20458,
              'weight': '100.5',
              'flags': [true, null],
            },
          }),
        ],
      ),
    );
    jsonEqual(raw.sessions.single.toJson()['raw'], {
      'date': 20458,
      'weight': '100.5',
      'flags': [true, null],
    });
  });

  test(
    'preview and apply reuse source identities atomically',
    () => _withStore((store, dir) async {
      final service = HistoryImportService(store);
      final preview = await service.preview(
        _parse(_document(measurements: [_measurement])),
      );
      equal(preview['applied'], false);
      equal(_counts(preview, 'sessions')['new'], 2);
      equal((await store.importedSessions()).length, 0);
      equal((await store.bodyMassRecords()).length, 0);
      final unconfirmed = await _failure(
        () => service.apply(
          _parse(_document()),
          at: DateTime.utc(2026, 2),
          atText: '2026-02-01T00:00:00Z',
          onChanged: 'reject',
          confirm: false,
        ),
      );
      equal(unconfirmed.code, 'validation');

      final first = await _apply(
        service,
        _document(measurements: [_measurement]),
      );
      equal(_counts(first, 'sessions')['new'], 2);
      equal(_counts(first, 'measurements')['new'], 1);
      final archived = canonicalJson((await store.archive()).toJson());
      // Imported history never becomes native sessions or revisions.
      equal((await store.sessions()).length, 0);
      equal((await store.revisions()).length, 0);
      final mass = (await store.bodyMassRecords()).single.measurement;
      equal(mass.context, 'imported-unclassified');
      equal(mass.source, 'bodytmi-history-import:old-log:body/1');

      final again = await _apply(
        service,
        _document(measurements: [_measurement]),
        at: '2026-03-01T10:00:00Z',
      );
      equal(_counts(again, 'sessions')['unchanged'], 2);
      equal(_counts(again, 'measurements')['unchanged'], 1);
      equal(canonicalJson((await store.archive()).toJson()), archived);

      // A corrected export conflicts by default and writes nothing, even
      // for an otherwise new session in the same document.
      final corrected = _document(measurements: [_measurement]);
      final sessions = corrected['sessions'] as List;
      final firstSession = jsonObject(sessions.first, 'session');
      firstSession['exercises'] = [
        _exercise(
          'h/1/1',
          [
            _set('a', 1, role: 'warmup', load: '60'),
            _set('b', 2, load: '102.5'),
          ],
          extra: {'exerciseId': 'squat'},
        ),
      ];
      sessions.add({
        'sourceId': 'h/3',
        'date': '2026-01-07',
        'exercises': [
          _exercise('h/3/1', [_set('a', 1, load: '110')]),
        ],
      });
      final rejected = await _failure(() => _apply(service, corrected));
      equal(rejected.code, 'conflict');
      equal(canonicalJson((await store.archive()).toJson()), archived);

      final updated = await _apply(
        service,
        corrected,
        at: '2026-03-02T10:00:00Z',
        onChanged: 'update',
      );
      equal(_counts(updated, 'sessions')['changed'], 1);
      equal(_counts(updated, 'sessions')['new'], 1);
      final record = await service.show('old-log', 'h/1');
      equal(record.contentVersion, 2);
      equal(record.importedAt, '2026-02-01T10:00:00Z');
      equal(record.updatedAt, '2026-03-02T10:00:00Z');

      // Records absent from a later export are reported, never deleted.
      final partial = await service.preview(
        _parse(
          _document(
            sessions: [
              jsonObject((corrected['sessions'] as List).last, 'last'),
            ],
          ),
        ),
      );
      jsonEqual(partial['absentSessions'], ['h/1', 'h/2']);
      jsonEqual(partial['absentMeasurements'], ['old-mass-1']);
      equal((await store.importedSessions()).length, 3);

      final stale = await _failure(
        () => service.delete('old-log', 'h/1', 1, confirm: true),
      );
      equal(stale.code, 'conflict');
      await _failure(() => service.delete('old-log', 'h/1', 2, confirm: false));
      await service.delete('old-log', 'h/1', 2, confirm: true);
      equal(
        (await _failure(() => service.show('old-log', 'h/1'))).code,
        'not_found',
      );
      // A different namespace is an independent identity space.
      final other = await _apply(service, _document(namespace: 'other-log'));
      equal(_counts(other, 'sessions')['new'], 2);
      equal((await service.list(namespace: 'other-log')).length, 2);
    }),
  );

  test(
    'imported measurements never take over foreign or deleted identities',
    () => _withStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      await mass.save({
        'id': 'old-mass-1',
        'context': 'health',
        'observedAt': '2026-01-04T07:00:00+01:00',
        'mass': _q('81', 'kg'),
      }, 0);
      final service = HistoryImportService(store);
      final document = _document(measurements: [_measurement]);
      final preview = await service.preview(_parse(document));
      final entry = jsonObject(
        (preview['measurements'] as List).single,
        'measurement',
      );
      equal(entry['status'], 'conflict');
      final error = await _failure(() => _apply(service, document));
      equal(error.code, 'conflict');
      equal((await store.importedSessions()).length, 0);

      final deleted = {..._measurement, 'id': 'gone'};
      await mass.save({
        'id': 'gone',
        'context': 'imported-unclassified',
        'observedAt': '2026-01-05T07:00:00+01:00',
        'mass': _q('82.5', 'kg'),
        'source': 'bodytmi-history-import:old-log:body/1',
      }, 0);
      await mass.delete('gone', 1, confirm: true);
      final reuse = await _failure(
        () => _apply(service, _document(sessions: [], measurements: [deleted])),
      );
      equal(reuse.code, 'conflict');
      // The health series was never touched.
      equal(
        (await mass.list(
          context: 'health',
        )).single.measurement.mass.enteredValue,
        '81',
      );
    }),
  );

  test(
    'imported series keep contexts separate and never invent times',
    () => _withStore((store, dir) async {
      final service = HistoryImportService(store);
      await _apply(
        service,
        _document(
          sessions: [
            {
              'sourceId': 'later',
              'startedAt': '2026-01-05T08:00:00+01:00',
              'exercises': [
                _exercise('e', [_set('a', 1, load: '100')]),
                _exercise('f', [
                  _set('a', 1, load: '220', unit: 'lb'),
                ], order: 2),
              ],
            },
            {
              'sourceId': 'earlier',
              'date': '2026-01-05',
              'exercises': [
                _exercise('e', [
                  _set('w', 1, role: 'warmup', load: '60'),
                  _set('a', 2, load: '95'),
                  _set('u', 3, role: 'unknown', load: '97.5'),
                ]),
                _exercise(
                  'm',
                  [_set('a', 1, load: '96')],
                  order: 2,
                  extra: {'exerciseId': 'squat'},
                ),
              ],
            },
            {
              'sourceId': 'january-9',
              'date': '2026-01-09',
              'exercises': [
                _exercise('e', [_set('a', 1, load: '102.5')]),
              ],
            },
          ],
        ),
      );
      final report = await service.series(metric: 'load');
      final series = [
        for (final s in report['series'] as List) s as Map<String, Object?>,
      ];
      String describe(Map<String, Object?> s) {
        final context = s['context'] as Map<String, Object?>;
        return '${context['exerciseId'] ?? context['exerciseName']}/'
            '${context['role']}/${context['unit']}';
      }

      jsonEqual([for (final s in series) describe(s)]..sort(), [
        'Squat/unknown/kg',
        'Squat/work/kg',
        'Squat/work/lb',
        'squat/work/kg',
      ]);
      final work = series.firstWhere((s) => describe(s) == 'Squat/work/kg');
      jsonEqual(
        [
          for (final p in work['points'] as List)
            [
              (p as Map<String, Object?>)['sessionSourceId'],
              p['datePrecision'],
              jsonObject(
                jsonObject(p['value'], 'value')['entered'],
                'entered',
              )['value'],
            ],
        ],
        [
          ['earlier', 'date', '95'],
          ['later', 'instant', '100'],
          ['january-9', 'date', '102.5'],
        ],
      );
      final warm = await service.series(
        metric: 'load',
        roles: {'warmup'},
        from: '2026-01-05',
        until: '2026-01-06',
      );
      equal((warm['series'] as List).length, 1);
      final ranged = await service.series(
        metric: 'load',
        exerciseName: 'Squat',
        from: '2026-01-06',
      );
      equal((ranged['series'] as List).length, 1);
      equal(
        (await _failure(
          () => service.series(metric: 'load', roles: {'heavy'}),
        )).code,
        'validation',
      );
    }),
  );

  test(
    'imported history is portable only under v64 formats',
    () => _withStore((store, dir) async {
      final service = HistoryImportService(store);
      await _apply(service, _document(measurements: [_measurement]));
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 64);
      final exported = await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      equal(exported['format'], 'bodytmi-logical-export/64');
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        equal(logical.archive.importedSessions.length, 2);
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
      }
      await store.close();
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await active.close();
      }
      active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
      } finally {
        await active.close();
      }

      // A non-empty section cannot claim the previous logical label...
      final envelope = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      final relabeled = copyJson(envelope)
        ..['format'] = 'bodytmi-logical-export/63';
      await File(
        '$dir/old-label.json',
      ).writeAsString(jsonEncode(await _resign(relabeled)));
      final logicalError = await _failure(
        () => LogicalArchiveFiles.prepare('$dir/old-label.json'),
      );
      check(
        logicalError.message.contains('importedSessions'),
        'older logical labels reject imported history',
      );
      // ...while an empty one is equivalent to its absence.
      final plain = copyJson(envelope)
        ..['format'] = 'bodytmi-logical-export/63';
      jsonObject(plain['data'], 'data')['importedSessions'] = <Object?>[];
      await File(
        '$dir/plain-label.json',
      ).writeAsString(jsonEncode(await _resign(plain)));
      final stripped = await LogicalArchiveFiles.prepare(
        '$dir/plain-label.json',
      );
      try {
        equal(stripped.archive.importedSessions.length, 0);
      } finally {
        await stripped.close();
      }
      // v64 requires the section.
      final missing = copyJson(envelope);
      jsonObject(missing['data'], 'data').remove('importedSessions');
      await File(
        '$dir/missing.json',
      ).writeAsString(jsonEncode(await _resign(missing)));
      final missingError = await _failure(
        () => LogicalArchiveFiles.prepare('$dir/missing.json'),
      );
      check(
        missingError.message.contains('imported history'),
        'v64 requires imported history sessions',
      );

      // Native relabels and tampered rows are rejected.
      final copy = '$dir/relabel.sqlite';
      File('$dir/native/database.sqlite').copySync(copy);
      final relabel = sqlite3.open(copy);
      relabel.userVersion = 63;
      relabel.close();
      await _failure(() => NativeBackup.validateDatabase(copy));
      final tamper = '$dir/tamper.sqlite';
      File('$dir/native/database.sqlite').copySync(tamper);
      final db = sqlite3.open(tamper);
      db.execute(
        "UPDATE imported_sessions SET source_id = 'forged' WHERE source_id = 'h/1'",
      );
      db.close();
      final tamperError = await _failure(
        () => NativeBackup.validateDatabase(tamper),
      );
      check(
        tamperError.message.contains('row identity mismatch'),
        'native validation checks imported row identity',
      );

      // A v63 profile migrates by adding the empty table.
      final legacy = '$dir/legacy.sqlite';
      final legacyStore = await TrainingStore.open(legacy);
      await StoredTrainingService(legacyStore).publish(definition(), 0);
      final before = canonicalJson((await legacyStore.archive()).toJson());
      await legacyStore.close();
      final old = sqlite3.open(legacy);
      old.execute('DROP TABLE imported_sessions');
      old.userVersion = 63;
      old.close();
      final upgraded = await TrainingStore.open(legacy);
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal((await HistoryImportService(upgraded).list()).length, 0);
      } finally {
        await upgraded.close();
      }
    }),
  );

  test(
    'history import CLI commands validate, preview, apply and query',
    () => _withStore((store, dir) async {
      await store.close();
      final request = example('history-import');
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          ...input,
        }),
      );

      final validated = await invoke([
        'import',
        'validate',
      ], jsonEncode({'schemaVersion': 1, 'document': request['document']}));
      equal(validated.code, 0);
      check(validated.output.contains('"dateOnlySessions":1'));
      final previewed = await cmd('import preview', {
        'document': request['document'],
      });
      equal(previewed.code, 0);
      check(previewed.output.contains('"applied":false'));
      final unconfirmed = await cmd('import apply', {
        'document': request['document'],
        'importedAt': '2026-02-01T10:00:00Z',
      });
      equal(unconfirmed.code, 2);
      equal(unconfirmed.output, '');
      final applied = await cmd('import apply', {
        'document': request['document'],
        'importedAt': '2026-02-01T10:00:00Z',
        'confirm': true,
      });
      equal(applied.code, 0);
      final replay = await cmd('import apply', {
        'document': request['document'],
        'importedAt': '2026-02-02T10:00:00Z',
        'confirm': true,
      });
      equal(replay.code, 0);
      check(replay.output.contains('"unchanged":2'));
      final changed = copyJson(request);
      final sessions = jsonObject(changed['document'], 'document')['sessions'];
      jsonObject((sessions as List).first, 'session')['name'] = 'Lower A2';
      final conflict = await cmd('import apply', {
        'document': changed['document'],
        'importedAt': '2026-02-03T10:00:00Z',
        'confirm': true,
      });
      equal(conflict.code, 5);
      final listed = await cmd('import list', {'namespace': 'old-log'});
      equal(listed.code, 0);
      check(listed.output.contains('"sourceId":"history/102"'));
      final shown = await cmd('import show', {
        'namespace': 'old-log',
        'sourceId': 'history/101',
      });
      equal(shown.code, 0);
      check(shown.output.contains('"Fire alarm"'));
      final missing = await cmd('import show', {
        'namespace': 'old-log',
        'sourceId': 'nope',
      });
      equal(missing.code, 3);
      final series = await cmd('import series', {'metric': 'load'});
      equal(series.code, 0);
      check(series.output.contains('"exerciseName":"DB Bench"'));
      final deleted = await cmd('import delete', {
        'namespace': 'old-log',
        'sourceId': 'history/102',
        'expectedVersion': 1,
        'confirm': true,
      });
      equal(deleted.code, 0);
    }),
  );

  test(
    'native series opt into a separate imported block',
    () => _withStore((store, dir) async {
      final service = HistoryImportService(store);
      await _apply(
        service,
        _document(
          sessions: [
            {
              'sourceId': 'dated',
              'date': '2026-01-04',
              'exercises': [
                _exercise(
                  'e',
                  [
                    _set('w', 1, role: 'warmup', load: '60'),
                    _set('u', 2, role: 'unknown', load: '90'),
                  ],
                  extra: {'exerciseId': 'squat'},
                ),
              ],
            },
            {
              'sourceId': 'timed',
              'startedAt': '2026-01-05T18:00:00+01:00',
              'exercises': [
                _exercise(
                  'e',
                  [_set('a', 1, load: '100')],
                  extra: {'exerciseId': 'squat', 'equipment': 'rack'},
                ),
                _exercise('f', [_set('a', 1, load: '40')], order: 2),
              ],
            },
          ],
        ),
      );
      final records = await store.importedSessions();
      Map<String, Object?> block({
        Map<String, Object?> context = const {},
        String? metric = 'load',
        DateTime? from,
        bool includeWarmups = false,
        List<String>? roles,
        FamilyRevision? family,
        int native = 0,
      }) => importedSeriesBlock(
        records,
        context: context,
        metric: metric,
        from: from,
        includeWarmups: includeWarmups,
        roles: roles,
        family: family,
        nativePointCount: native,
      );
      equal(block()['pointCount'], 3);
      equal(block(includeWarmups: true)['pointCount'], 4);
      // Explicit native roles cannot name the import-only unknown role.
      equal(block(roles: ['work'])['pointCount'], 2);
      equal(block(context: {'exercise': 'squat'})['pointCount'], 2);
      equal(
        block(
          context: {'exercise': 'squat', 'equipment': 'rack'},
        )['pointCount'],
        1,
      );
      final scoped = block(context: {'templateId': 'upper-a'});
      equal(scoped['pointCount'], 0);
      equal(jsonObject(scoped['excluded'], 'excluded')['all'], true);
      final bounded = block(from: DateTime.utc(2026));
      equal(bounded['pointCount'], 2);
      equal(jsonObject(bounded['excluded'], 'excluded')['dateOnlySessions'], 1);
      final family = FamilyRevision.publish(
        ExerciseFamily.fromJson({
          'id': 'squats',
          'name': 'Squats',
          'exercises': ['squat'],
        }),
      );
      // An unmapped exercise never joins a family by its source name.
      equal(block(family: family)['pointCount'], 2);
      equal(block(metric: null)['pointCount'], 6);
      equal((await _failure(() => block(native: 9999))).code, 'validation');

      await store.close();
      Future<Map<String, Object?>> series(Map<String, Object?> input) async {
        final result = await invoke(
          ['store', 'series'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '$dir/db.sqlite',
            ...input,
          }),
        );
        equal(result.code, 0);
        return jsonObject(
          jsonObject(jsonDecode(result.output), 'response')['data'],
          'data',
        );
      }

      final plain = await series({'metric': 'load'});
      check(!plain.containsKey('imported'), 'imported history is opt-in');
      final opted = await series({'metric': 'load', 'includeImported': true});
      final imported = jsonObject(opted['imported'], 'imported');
      equal(
        jsonObject(imported['policy'], 'policy')['id'],
        'bodytmi-imported-series/2',
      );
      equal(imported['pointCount'], 3);
      jsonEqual(opted['series'], plain['series']);
      final missing = await series({
        'metric': 'load',
        'includeImported': true,
        'importNamespace': 'nobody',
      });
      equal(jsonObject(missing['imported'], 'imported')['pointCount'], 0);
      final bad = await invoke(
        ['store', 'series'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'importNamespace': 'old-log',
        }),
      );
      equal(bad.code, 2);
    }),
  );
}
