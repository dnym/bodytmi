// Writes an invented demonstration profile for GUI development.
// Usage: dart run tool/demo_profile.dart PATH
import 'dart:io';

import 'package:bodytmi/bodytmi.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/demo_profile.dart PATH');
    exitCode = 64;
    return;
  }
  if (File(args.single).existsSync()) {
    stderr.writeln('${args.single} exists; choose a new path.');
    exitCode = 1;
    return;
  }
  await buildDemoProfile(args.single);
  stdout.writeln('Demo profile written to ${args.single}');
}
