import 'dart:convert';
import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'support.dart';

final Future<String> _cliExecutable = _compileCli();

/// The compiled native CLI, for tests that drive a process directly.
Future<String> cliExecutable() => _cliExecutable;
Future<String> _compileCli() =>
    compileNative('bin/bodytmi.dart', '.dart_tool/test_cli');
Future<String> compileNative(String target, String output) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    '--suppress-analytics',
    'build',
    'cli',
    '--target',
    target,
    '--output',
    output,
    '--root-package',
    'bodytmi',
  ]);
  if (result.exitCode != 0)
    throw StateError('${result.stdout} ${result.stderr}');
  final name = target.split('/').last.replaceAll('.dart', '');
  return File('$output/bundle/bin/$name').absolute.path;
}

Future<({int code, String output, String error})> invoke(
  List<String> args, [
  String? input,
]) async {
  final process = await Process.start(await _cliExecutable, args);
  final output = process.stdout.transform(utf8.decoder).join();
  final error = process.stderr.transform(utf8.decoder).join();
  if (input != null) process.stdin.write(input);
  await process.stdin.close();
  final code = await process.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      process.kill();
      throw StateError('CLI timed out.');
    },
  );
  return (code: code, output: await output, error: await error);
}

void cliTests() {
  test(
    'JSON CLI publishes, starts, completes, and finishes across processes',
    () async {
      Future<Map<String, Object?>> command(
        String name,
        Map<String, Object?> input,
      ) async {
        final result = await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, ...input}),
        );
        equal(result.code, 0);
        equal(result.error, '');
        final envelope = jsonObject(jsonDecode(result.output), 'response');
        return jsonObject(envelope['data'], 'data');
      }

      final published = await command('template publish', {
        'definition': definition().toJson(),
      });
      var session = await command('session start', {
        'id': 'cli-session',
        'revision': published,
        'startedAt': '2026-10-01T12:00:00Z',
      });
      final sets = session['sets']! as List<Object?>;
      for (final item in sets) {
        session = await command('session complete', {
          'session': session,
          'setId': jsonObject(item, 'set')['id'],
          'acceptSuggested': true,
        });
      }
      session = await command('session finish', {
        'session': session,
        'finishedAt': '2026-10-01T13:00:00Z',
      });
      equal(session['status'], 'finalized');
      final next = await command('session start', {
        'id': 'cli-next',
        'revision': published,
        'startedAt': '2026-10-02T12:00:00Z',
        'history': [session],
      });
      final first = jsonObject((next['sets']! as List<Object?>).first, 'set');
      check(jsonObject(first['sources'], 'sources').containsKey('mass'));
    },
  );
  test(
    'malformed input goes to stderr with validation exit code and empty stdout',
    () async {
      final result = await invoke(['quantity', 'normalize'], '{not-json');
      equal(result.code, 2);
      equal(result.output, '');
      equal(
        jsonObject(
          jsonObject(jsonDecode(result.error), 'response')['error'],
          'error',
        )['code'],
        'validation',
      );
    },
  );
  test(
    'unknown commands and fields fail rather than wait for prompts',
    () async {
      final unknown = await invoke(['unknown', 'command']);
      equal(unknown.code, 2);
      equal(unknown.output, '');
      rejects(
        () => const Commands().execute('template validate', {
          'schemaVersion': 1,
          'definition': definition().toJson(),
          'typo': true,
        }),
      );
    },
  );
  test(
    'CLI help and missing-file errors have a stable JSON boundary',
    () async {
      final help = await invoke(['--help']);
      equal(help.code, 0);
      equal(help.error, '');
      check(
        jsonObject(jsonDecode(help.output), 'help')['commands']
            is List<Object?>,
      );
      final missing = await invoke([
        'template',
        'publish',
        '--input',
        '/nonexistent/bodytmi.json',
      ]);
      equal(missing.code, 4);
      equal(missing.output, '');
    },
  );
  test(
    'domain and application packages have no I/O, Flutter, or storage imports',
    () {
      for (final package in ['bodytmi_core', 'bodytmi_application']) {
        for (final file in Directory(
          'packages/$package/lib',
        ).listSync(recursive: true).whereType<File>()) {
          for (final line in file.readAsLinesSync().where(
            (line) => line.startsWith('import ') || line.startsWith('export '),
          )) {
            check(
              !line.contains('dart:io') &&
                  !line.contains('flutter') &&
                  !line.contains('sqlite') &&
                  !line.contains('drift'),
              '${file.path}: $line',
            );
          }
        }
      }
    },
  );
}
