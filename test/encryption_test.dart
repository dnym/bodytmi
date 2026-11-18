import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

import 'cli_test.dart';
import 'support.dart';

/// Made with Python `cryptography` (OpenSSL Argon2id, whose key matched the
/// reference `argon2` CLI, and ChaCha20-Poly1305): an independent
/// implementation of `bodytmi-encrypted/1`. Passphrase `correct horse
/// battery`; plaintext `{"interop":"Python ✓"}`.
const _pythonEnvelope =
    '{"cipher":{"algorithm":"chacha20-poly1305","nonce":"ZGVmZ2hpamtsbW5v"},'
    '"ciphertext":"TBI/R0CLx5zj9VAT6Tohboe+DlUtmtAHffaqZac/TpIRbQ5Srnyzd9pjEiu/'
    'FHIezjW9dF1TzWLk5fNy","compression":"gzip","content":"test/1",'
    '"format":"bodytmi-encrypted/1","kdf":{"algorithm":"argon2id",'
    '"iterations":3,"memoryKiB":65536,"parallelism":1,'
    '"salt":"AAECAwQFBgcICQoLDA0ODw==","version":19}}';

const _marker = 'zebra-marker-2026';

void encryptionTests() {
  test('encrypted file envelope interoperates and authenticates', () async {
    final key = ProfileKey.fromText('correct horse battery\n');
    final plain = await EncryptedFile.open(
      utf8.encode(_pythonEnvelope),
      content: 'test/1',
      key: key,
      maxBytes: 1000,
    );
    equal(utf8.decode(plain), '{"interop":"Python ✓"}');
    Future<String> code(
      String text,
      ProfileKey k, [
      String c = 'test/1',
    ]) async {
      try {
        await EncryptedFile.open(
          utf8.encode(text),
          content: c,
          key: k,
          maxBytes: 1000,
        );
        return 'ok';
      } on BodyTmiException catch (e) {
        return e.code;
      }
    }

    equal(
      await code(_pythonEnvelope, ProfileKey.fromText('wrong pass')),
      'validation',
    );
    // Every header field is authenticated.
    final altered = jsonDecode(_pythonEnvelope) as Map<String, Object?>;
    (altered['cipher']! as Map)['nonce'] = base64.encode(List.filled(12, 7));
    equal(await code(jsonEncode(altered), key), 'validation');
    equal(await code(_pythonEnvelope, key, 'other/1'), 'validation');
    // Round trip with a fresh salt and nonce per file.
    final a = await EncryptedFile.seal([1, 2, 3], content: 'x/1', key: key);
    final b = await EncryptedFile.seal([1, 2, 3], content: 'x/1', key: key);
    check(utf8.decode(a) != utf8.decode(b), 'salt and nonce repeat');
    jsonEqual(
      await EncryptedFile.open(a, content: 'x/1', key: key, maxBytes: 3),
      [1, 2, 3],
    );
    rejects(() => ProfileKey.fromText(''));
    rejects(() => ProfileKey.fromText('short', newPassphrase: true));
  });

  test(
    'profile encryption: set, use, back up, export, rekey, remove',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-encryption-');
      final pw = '${dir.path}/pw',
          pw2 = '${dir.path}/pw2',
          xp = '${dir.path}/xp';
      await File(pw).writeAsString('correct horse battery\n');
      await File(pw2).writeAsString('another passphrase');
      await File(xp).writeAsString('export passphrase');
      await File('${dir.path}/short').writeAsString('short');
      var db = '${dir.path}/db.sqlite';

      Future<({int code, Map<String, Object?> body})> call(
        String name,
        Map<String, Object?> fields, {
        String? key,
        bool database = true,
      }) async {
        final r = await invoke(
          [
            ...name.split(' '),
            if (key != null) ...['--passphrase-file', key],
          ],
          jsonEncode({
            'schemaVersion': 1,
            if (database) 'database': db,
            ...fields,
          }),
        );
        final text = r.code == 0 ? r.output : r.error;
        return (code: r.code, body: jsonObject(jsonDecode(text), 'r'));
      }

      Future<Map<String, Object?>> ok(
        String name,
        Map<String, Object?> fields, {
        String? key,
        bool database = true,
      }) async {
        final r = await call(name, fields, key: key, database: database);
        check(r.code == 0, '$name: ${r.body}');
        final data = r.body['data'];
        return data is Map<String, Object?> ? data : {'list': data};
      }

      Future<String> fails(
        String name,
        Map<String, Object?> fields,
        int code, {
        String? key,
        bool database = true,
      }) async {
        final r = await call(name, fields, key: key, database: database);
        check(r.code == code, '$name: expected $code, got ${r.code} ${r.body}');
        return jsonObject(r.body['error'], 'error')['message']! as String;
      }

      Future<void> record(String id, {String? key}) => ok('mass record', {
        'measurement': {
          'id': id,
          'context': 'health',
          'observedAt': '2026-11-0${id.length}T07:00:00+01:00',
          'mass': {'value': '82.5', 'unit': 'kg'},
          'notes': _marker,
        },
      }, key: key);

      bool containsMarker(String path) {
        final file = File(path);
        if (!file.existsSync()) return false;
        return latin1.decode(file.readAsBytesSync()).contains(_marker);
      }

      Future<int> count({String? key}) async =>
          ((await ok('mass list', {'context': 'health'}, key: key))['list']!
                  as List)
              .length;

      try {
        await record('a');
        check(containsMarker(db) || containsMarker('$db-wal'), 'plain marker');
        equal((await ok('profile encryption', {}))['encrypted'], false);
        await fails('profile set-passphrase', {'passphraseFile': pw}, 2);
        await fails('profile set-passphrase', {
          'passphraseFile': '${dir.path}/short',
          'confirm': true,
        }, 2);
        await ok('profile set-passphrase', {
          'passphraseFile': pw,
          'confirm': true,
        });
        check(!containsMarker(db) && !containsMarker('$db-wal'), 'leak');
        // Writes under the key stay encrypted, WAL included.
        await record('bb', key: pw);
        check(!containsMarker(db) && !containsMarker('$db-wal'), 'WAL leak');
        equal(await count(key: pw), 2);
        check(
          (await fails('mass list', {
            'context': 'health',
          }, 4)).contains('--passphrase-file'),
          'missing key message',
        );
        check(
          (await fails(
            'mass list',
            {'context': 'health'},
            4,
            key: pw2,
          )).startsWith('Wrong passphrase'),
          'wrong key message',
        );
        final status = await ok('profile encryption', {}, key: pw2);
        equal(status['encrypted'], true);
        equal(status['passphraseChecked'], false);

        // Native backup: encrypted with the profile key.
        final backup = '${dir.path}/backup';
        final manifest = await ok('backup create', {
          'destination': backup,
        }, key: pw);
        equal(manifest['encrypted'], true);
        check(!containsMarker('$backup/database.sqlite'), 'backup leak');
        await fails('backup validate', {'source': backup}, 2, database: false);
        await ok(
          'backup validate',
          {'source': backup},
          key: pw,
          database: false,
        );
        final restoredDb = '${dir.path}/restored.sqlite';
        final saved = db;
        db = restoredDb;
        await ok('backup restore', {
          'source': backup,
          'recoveryDestination': '${dir.path}/recovery-1',
          'confirm': true,
        }, key: pw);
        equal(await count(key: pw), 2);

        // Logical export: plain on request, or its own passphrase.
        db = saved;
        await ok('archive export', {
          'destination': '${dir.path}/plain.json',
        }, key: pw);
        check(containsMarker('${dir.path}/plain.json'), 'plain export');
        final sealed = await ok('archive export', {
          'destination': '${dir.path}/sealed.json',
          'passphraseFile': xp,
        }, key: pw);
        equal(sealed['encrypted'], true);
        check(!containsMarker('${dir.path}/sealed.json'), 'export leak');
        await fails(
          'archive validate',
          {'source': '${dir.path}/sealed.json'},
          2,
          database: false,
        );
        await fails(
          'archive validate',
          {'source': '${dir.path}/sealed.json', 'passphraseFile': pw2},
          2,
          database: false,
        );
        await fails(
          'archive validate',
          {'source': '${dir.path}/plain.json', 'passphraseFile': xp},
          2,
          database: false,
        );
        final validated = await ok('archive validate', {
          'source': '${dir.path}/sealed.json',
          'passphraseFile': xp,
        }, database: false);
        equal(validated['encrypted'], true);
        // An encrypted export restores into a plain profile and into an
        // encrypted one (the profile keeps its own key).
        db = '${dir.path}/from-export.sqlite';
        await ok('archive restore', {
          'source': '${dir.path}/sealed.json',
          'passphraseFile': xp,
          'recoveryDestination': '${dir.path}/recovery-2',
          'confirm': true,
        });
        equal(await count(), 2);
        db = restoredDb;
        await record('ccc', key: pw);
        await ok('archive restore', {
          'source': '${dir.path}/sealed.json',
          'passphraseFile': xp,
          'recoveryDestination': '${dir.path}/recovery-3',
          'confirm': true,
        }, key: pw);
        equal(await count(key: pw), 2);
        check(!containsMarker(restoredDb), 'restored leak');
        // A plain backup cannot replace an encrypted profile.
        db = saved;
        final plainBackup = '${dir.path}/plain-backup';
        db = '${dir.path}/from-export.sqlite';
        await ok('backup create', {'destination': plainBackup});
        db = saved;
        await fails(
          'backup restore',
          {
            'source': plainBackup,
            'recoveryDestination': '${dir.path}/recovery-4',
            'confirm': true,
          },
          2,
          key: pw,
        );
        equal(await count(key: pw), 2);

        // Change, then remove the passphrase.
        await ok('profile set-passphrase', {
          'passphraseFile': pw2,
          'confirm': true,
        }, key: pw);
        await fails('mass list', {'context': 'health'}, 4, key: pw);
        equal(await count(key: pw2), 2);
        await fails('profile remove-passphrase', {}, 4);
        await ok('profile remove-passphrase', {'confirm': true}, key: pw2);
        equal(await count(), 2);
        await fails('mass list', {'context': 'health'}, 4, key: pw2);
        await fails('profile remove-passphrase', {'confirm': true}, 2);
        equal((await ok('profile encryption', {}))['encrypted'], false);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('a killed passphrase change leaves the previous key', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-rekey-kill-');
    final keys = ['${dir.path}/k0', '${dir.path}/k1'];
    await File(keys[0]).writeAsString('first passphrase');
    await File(keys[1]).writeAsString('second passphrase');
    final db = '${dir.path}/db.sqlite';
    try {
      // About 6 MB of entries so the rewrite takes measurable time.
      final store = await TrainingStore.open(db);
      try {
        await store.transaction(() async {
          for (var i = 0; i < 20000; i++) {
            await store.saveDiaryEntry(
              DiaryEntry.fromJson({
                'id': 'e$i',
                'at': '2026-11-01T12:00:00+01:00',
                'notes': '$_marker ${'x' * 200}',
                'quick': {
                  'energy': {'value': '$i', 'unit': 'kcal'},
                },
              }),
            );
          }
        });
      } finally {
        await store.close();
      }
      Future<int?> entries(String? key) async {
        try {
          return await withProfileKey(
            key == null ? null : await ProfileKey.readFile(key),
            () async {
              final s = await TrainingStore.open(db);
              try {
                return (await s.diaryEntries()).length;
              } finally {
                await s.close();
              }
            },
          );
        } on BodyTmiException {
          return null;
        }
      }

      final exe = await cliExecutable();
      String? current;
      var changed = 0, interrupted = 0;
      final random = Random(7);
      for (var round = 0; round < 8; round++) {
        final next = current == keys[0] ? keys[1] : keys[0];
        final child = await Process.start(exe, [
          'profile',
          'set-passphrase',
          if (current != null) ...['--passphrase-file', current],
        ]);
        child.stdin.write(
          jsonEncode({
            'schemaVersion': 1,
            'database': db,
            'passphraseFile': next,
            'confirm': true,
          }),
        );
        await child.stdin.close();
        await Future<void>.delayed(
          Duration(milliseconds: 20 + random.nextInt(200)),
        );
        child.kill(ProcessSignal.sigkill);
        final code = await child.exitCode;
        final before = await entries(current), after = await entries(next);
        check(
          (before == null) != (after == null),
          'round $round: exactly one key opens the profile '
          '(exit $code, before $before, after $after)',
        );
        equal(before ?? after, 20000);
        if (after != null) {
          current = next;
          changed++;
        } else {
          interrupted++;
        }
      }
      check(changed + interrupted == 8);
      stdout.writeln(
        'rekey kills: $changed completed, $interrupted interrupted',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
