import 'package:material_ui/material_ui.dart';

/// The probe has no user interface of its own; its integration tests run the
/// unmodified pure Dart storage stack inside an Android app process.
void main() => runApp(
  const MaterialApp(
    home: Scaffold(body: Center(child: Text('BodyTMI Android probe'))),
  ),
);
