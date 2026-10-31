import 'dart:async';
import 'dart:convert';

import 'package:bodytmi_core/bodytmi_core.dart';

typedef TestCase = ({String name, FutureOr<void> Function() body});
final tests = <TestCase>[];
void test(String name, FutureOr<void> Function() body) =>
    tests.add((name: name, body: body));
void check(bool condition, [String message = 'Check failed']) {
  if (!condition) throw StateError(message);
}

void equal(Object? actual, Object? expected) {
  if (actual != expected)
    throw StateError('Expected $expected, received $actual.');
}

void jsonEqual(Object? actual, Object? expected) =>
    equal(jsonEncode(actual), jsonEncode(expected));
void rejects(void Function() action, [String code = 'validation']) {
  try {
    action();
  } on BodyTmiException catch (error) {
    equal(error.code, code);
    return;
  }
  throw StateError('Expected BodyTmiException($code).');
}
