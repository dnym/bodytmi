import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty ||
        (arguments.length == 1 && arguments.single == '--help')) {
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'commands': [...commandNames, ...storedCommandNames],
          'usage': 'bodytmi <group> <action> [--input FILE|-]',
          'input': 'One JSON request, schemaVersion: 1, from stdin or --input.',
          'storage':
              'store commands require a database path in the JSON request. Existing commands use explicit snapshots.',
        }),
      );
      return;
    }
    if (arguments.length == 1 && arguments.single == '--version') {
      stdout.writeln(jsonEncode({'schemaVersion': 1, 'version': '0.1.0'}));
      return;
    }
    if (arguments.length != 2 && arguments.length != 4) {
      throw const BodyTmiException(
        'usage',
        'Expected <group> <action> [--input FILE|-].',
      );
    }
    final command = arguments.take(2).join(' ');
    if ((!commandNames.contains(command) &&
            !storedCommandNames.contains(command)) ||
        (arguments.length == 4 && arguments[2] != '--input')) {
      throw const BodyTmiException(
        'usage',
        'Unknown command/option. Use --help.',
      );
    }
    const maxBytes = 8 * 1024 * 1024;
    final inputPath = arguments.length == 4 ? arguments[3] : '-';
    final stream = inputPath == '-' ? stdin : File(inputPath).openRead();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes)
        invalid('Request exceeds the 8 MiB resource limit.');
      bytes.add(chunk);
    }
    final request = jsonObject(
      jsonDecode(utf8.decode(bytes.takeBytes())),
      'request',
    );
    final response = storedCommandNames.contains(command)
        ? await executeStored(command, request)
        : const Commands().execute(command, request);
    stdout.writeln(jsonEncode(response));
  } on BodyTmiException catch (error) {
    _error(error.code, error.message);
    exitCode = switch (error.code) {
      'not_found' => 3,
      'conflict' || 'in_use' => 5,
      'storage' => 4,
      _ => 2,
    };
  } on FormatException catch (error) {
    _error('validation', 'Invalid JSON/text: ${error.message}');
    exitCode = 2;
  } on SqliteException catch (error) {
    _error('storage', error.message);
    exitCode = 4;
  } on FileSystemException catch (error) {
    _error('io', error.message);
    exitCode = 4;
  } catch (error, stack) {
    _error('internal', '$error');
    stderr.writeln(stack);
    exitCode = 70;
  }
}

void _error(String code, String message) => stderr.writeln(
  jsonEncode({
    'schemaVersion': 1,
    'error': {'code': code, 'message': message},
  }),
);
